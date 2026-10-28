# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CredentialFile,
    [Parameter(Mandatory)][string]$ScratchParent,
    [Parameter(Mandatory)][string]$PublishDirectory,
    [Parameter(Mandatory)][string]$AnalyzerDirectory,
    [ValidateRange(1,120)][int]$Seconds=5,
    [ValidateRange(1,1024)][int]$Connections=256,
    [ValidateRange(1,1048576)][int]$PayloadBytes=65536
)
$ErrorActionPreference='Stop'
$sourceRoot=Split-Path $PSScriptRoot
$diagnostics=Join-Path $ScratchParent 'managed-gc-diagnostics'
$publishOwned=$false
$peer=$null;$peerOwned=$false;$profileOwned=$false
$client=$null;$localServer=$null;$tcpProbe=$null;$clrProbe=$null
$failure=$null;$cleanupErrors=[Collections.Generic.List[Exception]]::new()
$phase='preflight';$start=$null;$end=$null;$result=$null
$port=20300;$count=8192;$heapMiB=512
$rate=[int][Math]::Ceiling($count/[double]$Seconds)
$analyzer=Join-Path $AnalyzerDirectory 'CpuSamples.exe'
$exe=Join-Path $diagnostics 'ArrivalTcp.exe'
$compiler="$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$wpr="$env:SystemRoot\System32\wpr.exe"
function Wait-Ready($Child,[string]$File) {
    $clock=[Diagnostics.Stopwatch]::StartNew()
    while(-not(Test-Path -LiteralPath $File)) {
        if($Child.Process.HasExited -or $clock.Elapsed.TotalSeconds -gt 20){throw 'An owned diagnostic process did not become ready.'}
        Start-Sleep -Milliseconds 50
    }
}
try {
    $phase='publication-init'
    $null=New-Item -ItemType Directory -Path $diagnostics -ErrorAction Stop
    $null=New-Item -ItemType Directory -Path $PublishDirectory -ErrorAction Stop
    $publishOwned=$true
    $phase='credential-import'
    try {$credential=Import-Clixml -LiteralPath $CredentialFile}
    finally {if(Test-Path -LiteralPath $CredentialFile){Remove-Item -LiteralPath $CredentialFile -ErrorAction Stop}}
    $phase='module-load'
    Import-Module (Join-Path $PSScriptRoot 'WindowsCts.psm1') -Force
    $phase='preflight'
    if(@(Get-Process -Name Runner.Worker,ctsTraffic,ArrivalTcp -ErrorAction Ignore).Count){throw 'Client guest is busy.'}
    if((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory*1024 -lt $heapMiB*4MB){throw 'Insufficient free guest memory for the bounded GC diagnostic.'}
    if(-not(Test-Path -LiteralPath $analyzer)){throw 'The public-source analyzer is missing.'}
    $phase='peer-connect'
    $peer=New-PSSession -ComputerName netperf-peer -Credential $credential -ConfigurationName PowerShell.7
    $clientIdentity=(Get-CimInstance Win32_ComputerSystemProduct).UUID
    $peerIdentity=Invoke-Command -Session $peer -ScriptBlock {(Get-CimInstance Win32_ComputerSystemProduct).UUID}
    if([string]::IsNullOrWhiteSpace($clientIdentity) -or [string]::IsNullOrWhiteSpace($peerIdentity) -or $clientIdentity -eq $peerIdentity) {
        throw 'Two distinct guest identities must be verified before running traffic.'
    }
    $peerAddress=@([Net.Dns]::GetHostAddresses('netperf-peer')|Where-Object AddressFamily -eq InterNetwork)[0].ToString()
    if([Net.IPAddress]::IsLoopback([Net.IPAddress]::Parse($peerAddress))){throw 'The remote peer resolved to loopback.'}
    $route=@(Find-NetRoute -RemoteIPAddress $peerAddress|Where-Object{$_.PSObject.Properties['IPAddress']})
    if($route.Count -ne 1){throw 'A unique client-to-peer route is required.'}
    $clientAddress=$route[0].IPAddress;$alias=$route[0].InterfaceAlias
    $ipInterface=@(Get-NetIPInterface -InterfaceIndex $route[0].InterfaceIndex -AddressFamily IPv4)
    if($ipInterface.Count -ne 1 -or $ipInterface[0].NlMtu -lt 1){throw 'A unique client data interface with positive MTU is required.'}
    $mtu=$ipInterface[0].NlMtu
    $remote=Invoke-Command -Session $peer -ScriptBlock {
        if(@(Get-Process -Name Runner.Worker,ctsTraffic,ArrivalTcp -ErrorAction Ignore).Count){throw 'Peer guest is busy.'}
        $root=Join-Path $env:TEMP ('managed-gc-peer-'+[guid]::NewGuid().ToString('N'))
        $null=New-Item -ItemType Directory -Path $root
        $root
    }
    foreach($file in @('ArrivalTcp.cs','ArrivalTcp.ServerGc.config')) {
        Copy-Item -LiteralPath (Join-Path $sourceRoot $file) -Destination (Join-Path $remote $file) -ToSession $peer
    }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'WindowsCts.psm1') -Destination (Join-Path $remote 'WindowsCts.psm1') -ToSession $peer
    $phase='compile-client'
    $null=Invoke-TcpChurnTool -Program $compiler -Arguments @('/nologo','/target:exe','/platform:x64',"/out:$exe",(Join-Path $sourceRoot 'ArrivalTcp.cs')) `
        -Directory $diagnostics -LogPrefix (Join-Path $diagnostics 'compile')
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'ArrivalTcp.ServerGc.config') -Destination ($exe+'.config')
    $peerOwned=$true
    $phase='start-remote-peer'
    Invoke-Command -Session $peer -ScriptBlock {
        param($root,$listen,$client,$port,$count,$rate,$payloadBytes)
        if(@(Get-NetIPAddress -AddressFamily IPv4|Where-Object IPAddress -eq $listen).Count -ne 1){throw 'The peer does not uniquely own the declared listen address.'}
        Import-Module (Join-Path $root 'WindowsCts.psm1') -Force
        $global:OwnedManagedGcPeer=@{Process=$null;Rule=$null;Root=$root}
        $compiler="$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
        $exe=Join-Path $root 'ArrivalTcp.exe'
        $null=Invoke-TcpChurnTool -Program $compiler -Arguments @('/nologo','/target:exe','/platform:x64',"/out:$exe",(Join-Path $root 'ArrivalTcp.cs')) `
            -Directory $root -LogPrefix (Join-Path $root 'compile')
        Copy-Item -LiteralPath (Join-Path $root 'ArrivalTcp.ServerGc.config') -Destination ($exe+'.config')
        $rule='ManagedGcPeer-'+[guid]::NewGuid().ToString('N')
        $null=New-NetFirewallRule -Name $rule -DisplayName $rule -Direction Inbound -Action Allow `
            -Protocol TCP -LocalPort $port -LocalAddress $listen -RemoteAddress $client
        $global:OwnedManagedGcPeer.Rule=$rule
        $output=Join-Path $root 'server.json'
        $global:OwnedManagedGcPeer.Process=Start-TcpChurnCollector -Program $exe -Arguments @(
            $client,$listen,[string]$port,[string]$count,[string]$rate,[string]$payloadBytes,$output,'server',[string]$payloadBytes,'14529','256','nodelay'
        ) -Directory $root -LogPrefix (Join-Path $root 'server')
        $clock=[Diagnostics.Stopwatch]::StartNew()
        while(-not(Test-Path -LiteralPath ($output+'.ready'))) {
            if($global:OwnedManagedGcPeer.Process.Process.HasExited -or $clock.Elapsed.TotalSeconds -gt 20){throw 'Peer listener did not become ready.'}
            Start-Sleep -Milliseconds 50
        }
    } -ArgumentList $remote,$peerAddress,$clientAddress,$port,($count/2),$rate,$payloadBytes
    $localOutput=Join-Path $diagnostics 'loopback.json'
    $phase='start-loopback-peer'
    $localServer=Start-TcpChurnCollector -Program $exe -Arguments @(
        '127.0.0.1','127.0.0.2',[string]$port,[string]($count/2),[string]$rate,[string]$payloadBytes,$localOutput,'server',[string]$payloadBytes,'14529','256','nodelay'
    ) -Directory $diagnostics -LogPrefix (Join-Path $diagnostics 'loopback')
    Wait-Ready $localServer ($localOutput+'.ready')
    $phase='trace-start'
    $null=Invoke-TcpChurnTool -Program $wpr -Arguments @('-start','CPU','-filemode') -Directory $diagnostics -LogPrefix (Join-Path $diagnostics 'wpr-start')
    $profileOwned=$true
    $provider=Get-WinEvent -ListProvider Microsoft-Windows-TCPIP
    $tasks=@('TcpTcbSynSend','TcpDisconnectTcbRtoTimeout','TcpDataTransferRetransmitRound',
        'TcpBlackHoleDetectionEntry','TcpBlackHoleDetectionExit','TcpBlackHoleDetectionFailed','TcpBhDetectFullSizeAck')
    $events=@($provider.Events|Where-Object{$null -ne $_.Task -and $_.Task.Name -in $tasks}|
        ForEach-Object{[pscustomobject]@{Id=$_.Id;Task=$_.Task.Name}})
    foreach($task in $tasks){if($task -notin @($events.Task)){throw 'A required public TCP event is unavailable.'}}
    $tcpState=Join-Path $diagnostics 'tcp-state.json'
    @{publicProviderGuid=[string]$provider.Id;publicProviderEvents=$events}|ConvertTo-Json -Depth 4|Set-Content $tcpState
    $clrState=Join-Path $diagnostics 'clr-state.json'
    @{publicProviderGuid='e13c0d23-ccbc-4e12-931b-d9cc2eee27e4';publicProviderEvents=@(
        @{Id=1;Task='GCStart'},@{Id=2;Task='GCStop'},@{Id=3;Task='GCRestartEEEnd'},
        @{Id=7;Task='GCRestartEEBegin'},@{Id=8;Task='GCSuspendEEEnd'},@{Id=9;Task='GCSuspendEEBegin'}
    )}|ConvertTo-Json -Depth 4|Set-Content $clrState
    $tcpProbe=Start-TcpChurnCollector -Program $analyzer -Arguments @('--capture-probes',(Join-Path $diagnostics 'tcp.etl'),
        $tcpState,(Join-Path $diagnostics 'tcp.ready'),(Join-Path $diagnostics 'tcp.stop'),'300') `
        -Directory $diagnostics -LogPrefix (Join-Path $diagnostics 'tcp-capture')
    Wait-Ready $tcpProbe (Join-Path $diagnostics 'tcp.ready')
    $clrProbe=Start-TcpChurnCollector -Program $analyzer -Arguments @('--capture-probes',(Join-Path $diagnostics 'clr.etl'),
        $clrState,(Join-Path $diagnostics 'clr.ready'),(Join-Path $diagnostics 'clr.stop'),'300') `
        -Directory $diagnostics -LogPrefix (Join-Path $diagnostics 'clr-capture')
    Wait-Ready $clrProbe (Join-Path $diagnostics 'clr.ready')
    $before=Get-NetAdapterStatistics -Name $alias
    $start=[DateTime]::UtcNow.ToString('o')
    $phase='managed-gc-traffic'
    $clientOutput=Join-Path $diagnostics 'client.json'
    $client=Start-TcpChurnCollector -Program $exe -Arguments @(
        "$clientAddress,127.0.0.1","$peerAddress,127.0.0.2",[string]$port,[string]$count,[string]$rate,[string]$payloadBytes,
        $clientOutput,'client',[string]$payloadBytes,'14529',[string]$Connections,'nodelay',"gc:${heapMiB}:2048"
    ) -Directory $diagnostics -LogPrefix (Join-Path $diagnostics 'client')
    $clientPid=$client.Process.Id
    if(-not $client.Process.WaitForExit(180000) -or $client.Process.ExitCode -ne 0){throw 'The GC client did not complete successfully.'}
    $end=[DateTime]::UtcNow.ToString('o')
    if(-not $localServer.Process.WaitForExit(10000) -or $localServer.Process.ExitCode -ne 0){throw 'The owned loopback server did not complete.'}
    $remoteResult=Invoke-Command -Session $peer -ScriptBlock {
        $child=$global:OwnedManagedGcPeer.Process
        if(-not $child.Process.WaitForExit(10000) -or $child.Process.ExitCode -ne 0){throw 'The owned remote server did not complete.'}
        Get-Content (Join-Path $global:OwnedManagedGcPeer.Root 'server.json') -Raw|ConvertFrom-Json
    }
    $r=Get-Content $clientOutput -Raw|ConvertFrom-Json
    $l=Get-Content $localOutput -Raw|ConvertFrom-Json
    foreach($entry in @($r,$l,$remoteResult)) {
        if($entry.outcome -ne 'collected' -or $entry.networkErrors -ne 0 -or $entry.protocolErrors -ne 0 -or $entry.barrier -ne $false) {
            throw 'A mixed-traffic endpoint failed verification.'
        }
    }
    if($r.targets.Count -ne 2 -or $r.targets[0].loopback -or -not $r.targets[1].loopback -or
        $r.targets[0].connections -ne $remoteResult.connections -or $r.targets[1].connections -ne $l.connections -or
        $r.targets[0].requestBytes -ne $remoteResult.bytesReceived -or $r.targets[0].responseBytes -ne $remoteResult.bytesSent -or
        $r.targets[1].requestBytes -ne $l.bytesReceived -or $r.targets[1].responseBytes -ne $l.bytesSent -or
        -not $r.managedGc.enabled -or $r.managedGc.gen2CollectionsAfter -le $r.managedGc.gen2CollectionsBefore) {
        throw 'Mixed-target byte counts or real managed-GC coverage did not verify.'
    }
    $after=Get-NetAdapterStatistics -Name $alias
    if($after.SentBytes-$before.SentBytes -lt $r.targets[0].requestBytes -or
        $after.ReceivedBytes-$before.ReceivedBytes -lt $r.targets[0].responseBytes){throw 'The non-loopback NIC did not account for the remote payload.'}
    $result=[ordered]@{schema=1;workload='managed-gc-mixed';outcome='collected';connections=$r.connections
        bytesSent=$r.bytesSent;bytesReceived=$r.bytesReceived;payloadBytesPerDirection=$payloadBytes
        dataInterfaceMtuBytes=$mtu
        targets=$r.targets;managedGc=$r.managedGc
        arrivalRate=$r.arrivalRate;maxLaunchLagMilliseconds=$r.maxLaunchLagMilliseconds
        cpuCoverage='sampled-etw-only';executionTopology='two-existing-guests-plus-client-loopback'
        targetSeverity='not-evaluated';conclusion='diagnostic-not-customer-severity-proof'}
}catch{$failure=$_}
finally {
    foreach($child in @($client,$localServer)){if($null -ne $child){try{Stop-TcpChurnCollector $child}catch{$cleanupErrors.Add($_.Exception)}}}
    foreach($entry in @(@{child=$tcpProbe;stop='tcp.stop'},@{child=$clrProbe;stop='clr.stop'})) {
        if($null -eq $entry.child){continue}
        try {
            [IO.File]::WriteAllText((Join-Path $diagnostics $entry.stop),'stop')
            if(-not $entry.child.Process.WaitForExit(20000) -or $entry.child.Process.ExitCode -ne 0){throw 'An owned probe did not close cleanly.'}
        }catch{$cleanupErrors.Add($_.Exception)}
        finally{try{Stop-TcpChurnCollector $entry.child}catch{$cleanupErrors.Add($_.Exception)}}
    }
    if($profileOwned) {
        try {$null=Invoke-TcpChurnTool -Program $wpr -Arguments @('-stop',(Join-Path $diagnostics 'cpu.etl')) `
            -Directory $diagnostics -LogPrefix (Join-Path $diagnostics 'wpr-stop') -TimeoutSeconds 120}
        catch{$cleanupErrors.Add($_.Exception)}
    }
    if($peerOwned -and $null -ne $peer) {
        try {Invoke-Command -Session $peer -ScriptBlock {
            try {if($null -ne $global:OwnedManagedGcPeer.Process){Stop-TcpChurnCollector $global:OwnedManagedGcPeer.Process}}
            finally {if($global:OwnedManagedGcPeer.Rule){Remove-NetFirewallRule -Name $global:OwnedManagedGcPeer.Rule -ErrorAction Stop}}
        }}catch{$cleanupErrors.Add($_.Exception)}
    }
    if($null -ne $peer){try{Remove-PSSession $peer -ErrorAction Stop}catch{$cleanupErrors.Add($_.Exception)}}
}
if($null -ne $failure -or $cleanupErrors.Count) {
    if($publishOwned) {
        $type=if($null -ne $failure){$failure.Exception.GetType().FullName}else{'cleanup-failure'}
        $code=if($null -ne $failure){$failure.Exception.HResult}else{$null}
        $toolCode=if($null -ne $failure -and $failure.Exception.Data.Contains('ToolExitCode')){$failure.Exception.Data['ToolExitCode']}else{$null}
        @{schema=1;workload='managed-gc-mixed';outcome='failed';phase=$phase;failureType=$type;failureCode=$code
            toolExitCode=$toolCode;cleanupErrorCount=$cleanupErrors.Count;cleanupVerified=($cleanupErrors.Count -eq 0)
            conclusion='no-accepted-measurement'}|ConvertTo-Json|Set-Content (Join-Path $PublishDirectory 'result.json')
    }
    if($null -ne $failure){$cleanupErrors.Insert(0,$failure.Exception)}
    throw [AggregateException]::new('Managed-GC diagnostic or required cleanup failed.',$cleanupErrors)
}
$phase='public-symbol-analysis'
try {
    $phase='analyze-whole-cpu'
    $null=Invoke-TcpChurnTool -Program $analyzer -Arguments @((Join-Path $diagnostics 'cpu.etl'),
        (Join-Path $PublishDirectory 'cpu-load.json'),$start,$end) -Directory $diagnostics `
        -LogPrefix (Join-Path $diagnostics 'cpu-analysis') -TimeoutSeconds 300
    $postStart=([datetime]$r.managedGc.collectionEndUtc).ToUniversalTime()
    $endUtc=([datetime]$end).ToUniversalTime()
    $postEnd=if($postStart.AddSeconds(2) -lt $endUtc){$postStart.AddSeconds(2)}else{$endUtc}
    if($postEnd -le $postStart){throw 'No positive post-collection window remains.'}
    $phase='analyze-post-gc-cpu'
    $null=Invoke-TcpChurnTool -Program $analyzer -Arguments @((Join-Path $diagnostics 'cpu.etl'),
        (Join-Path $PublishDirectory 'cpu-after-gc.json'),$postStart.ToString('o'),$postEnd.ToString('o')) `
        -Directory $diagnostics -LogPrefix (Join-Path $diagnostics 'post-gc-analysis') -TimeoutSeconds 300
    $phase='analyze-tcp-events'
    $null=Invoke-TcpChurnTool -Program $analyzer -Arguments @('--events',(Join-Path $diagnostics 'tcp.etl'),
        (Join-Path $PublishDirectory 'tcp-events.json'),'interval',$start,$end,(Join-Path $diagnostics 'tcp-state.json')) `
        -Directory $diagnostics -LogPrefix (Join-Path $diagnostics 'tcp-analysis') -TimeoutSeconds 120
    $tcpSummary=Get-Content (Join-Path $PublishDirectory 'tcp-events.json') -Raw|ConvertFrom-Json
    if($tcpSummary.outcome -ne 'counted' -or $tcpSummary.eventsLost -ne 0){throw 'Lossless TCP event coverage is required.'}
    $phase='analyze-clr-events'
    $null=Invoke-TcpChurnTool -Program $analyzer -Arguments @('--events',(Join-Path $diagnostics 'clr.etl'),
        (Join-Path $diagnostics 'clr-loss.json'),'interval',$start,$end,(Join-Path $diagnostics 'clr-state.json')) `
        -Directory $diagnostics -LogPrefix (Join-Path $diagnostics 'clr-loss-analysis') -TimeoutSeconds 120
    $clrSummary=Get-Content (Join-Path $diagnostics 'clr-loss.json') -Raw|ConvertFrom-Json
    if($clrSummary.outcome -ne 'counted' -or $clrSummary.eventsLost -ne 0){throw 'Lossless CLR event coverage is required.'}
    $startUtc=([datetime]$start).ToUniversalTime()
    $gcRecords=@(Get-WinEvent -Path (Join-Path $diagnostics 'clr.etl') -Oldest|Where-Object{
        $_.ProcessId -eq $clientPid -and $_.TimeCreated.ToUniversalTime() -ge $startUtc -and $_.TimeCreated.ToUniversalTime() -le $endUtc
    })
    if(-not $gcRecords.Count -or $gcRecords.Count -gt 1024){throw 'Owned-process CLR event coverage is missing or exceeds its bound.'}
    $gcCounts=@{}
    foreach($event in $gcRecords){$key=[string]$event.Id;if(-not $gcCounts.ContainsKey($key)){$gcCounts[$key]=0};$gcCounts[$key]++}
    if(-not $gcCounts.ContainsKey('8') -or -not $gcCounts.ContainsKey('7')){throw 'CLR suspension/restart events did not verify.'}
    @{schema=1;processFilterApplied=$true;eventCounts=$gcCounts;eventsLost=0;scope='owned-client-process-workload-interval';
        conclusion='event-coverage-not-exact-pause-correlation'}|ConvertTo-Json -Depth 4|Set-Content (Join-Path $PublishDirectory 'clr-events.json')
    foreach($file in @('cpu-load.json','cpu-after-gc.json')) {
        $cpu=Get-Content (Join-Path $PublishDirectory $file) -Raw|ConvertFrom-Json
        if($cpu.outcome -ne 'sampled' -or $cpu.eventsLost -ne 0 -or $cpu.unresolvedNetworkFrames -ne 0){throw 'Lossless matching public-symbol CPU attribution is required.'}
    }
    $result.cleanupVerified=$true
    $result|ConvertTo-Json -Depth 6|Set-Content (Join-Path $PublishDirectory 'result.json')
}catch {
    $toolCode=if($_.Exception.Data.Contains('ToolExitCode')){$_.Exception.Data['ToolExitCode']}else{$null}
    @{schema=1;workload='managed-gc-mixed';outcome='failed';phase=$phase;failureType=$_.Exception.GetType().FullName
        failureCode=$_.Exception.HResult;toolExitCode=$toolCode;cleanupVerified=$true;conclusion='analysis-not-accepted'}|
        ConvertTo-Json|Set-Content (Join-Path $PublishDirectory 'result.json')
    throw
}
