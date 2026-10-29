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
    [ValidateRange(1,1048576)][int]$PayloadBytes=65536,
    [switch]$PeerRecovery,
    [switch]$IsolatedData,
    [ValidateRange(100,8000)][int]$RecoveryMilliseconds=8000,
    [ValidateSet('client','server')][string]$GcProcessRole='client',
    [ValidateSet('arrays','graph')][string]$HeapLayout='arrays',
    [switch]$RouteRefresh,
    [ValidateSet('onlink','peer-gateway','destination-flush')][string]$RouteVariant='onlink',
    [ValidateSet(0,16384)][int]$ReceiveBudgetBytes=0,
    [ValidateSet(0,1,1024,8192,24576,49152)][int]$CacheRetirePaths=0,
    [switch]$WprProbes,
    [switch]$PeerGcPressure,
    [string]$CacheInterfaceAlias,
    [string]$CacheInterfaceGuid,
    [switch]$SpinLocks,
    [string]$DataInterfaceAlias,
    [string]$DataInterfaceGuid
)
$ErrorActionPreference='Stop'
if($GcProcessRole -eq 'server' -and (-not $IsolatedData -or $PeerRecovery)){
    throw 'Receiver GC requires isolated data and no neighbor pulse.'
}
if($RouteRefresh -and ($GcProcessRole -ne 'server' -or -not $IsolatedData -or $PeerRecovery)){
    throw 'Route refresh requires isolated receiver-GC mode without a neighbor pulse.'
}
if($RouteVariant -ne 'onlink' -and -not $RouteRefresh){throw 'Logical gateway selection requires the owned route-refresh control.'}
if($RouteVariant -eq 'destination-flush' -and ($CacheRetirePaths -or $CacheInterfaceAlias -or $PeerGcPressure)){
    throw 'Destination-cache flush requires an isolated control without cache retirement or companion pressure.'
}
if($ReceiveBudgetBytes -and $GcProcessRole -ne 'server'){throw 'A bounded receive budget requires receiver-GC mode.'}
if($SpinLocks -and -not $WprProbes){throw 'Owned spinlock capture requires the exact-event WPR controller.'}
if(($DataInterfaceAlias -or $DataInterfaceGuid) -and
    (-not $IsolatedData -or $DataInterfaceAlias -notmatch '^NetperfData-[0-9a-f]{12}$' -or -not $DataInterfaceGuid)){
    throw 'Disposable data transport requires an identity-matched isolated data interface.'
}
if($PeerGcPressure -and ($GcProcessRole -ne 'server' -or -not $IsolatedData -or $PeerRecovery)){
    throw 'Peer GC pressure requires isolated receiver GC without a neighbor fault.'
}
if($CacheRetirePaths -and ($GcProcessRole -ne 'server' -or -not $IsolatedData -or $PeerRecovery)){
    throw 'Cache retirement requires isolated receiver GC without a neighbor fault.'
}
if(($CacheInterfaceAlias -or $CacheInterfaceGuid) -and
    (-not $CacheRetirePaths -or $CacheInterfaceAlias -notmatch '^NetperfPath-[0-9a-f]{12}$' -or -not $CacheInterfaceGuid)){
    throw 'Unused-interface retirement requires the owned disposable interface and a bounded cache population.'
}
$sourceRoot=Split-Path $PSScriptRoot
$diagnostics=Join-Path $ScratchParent 'managed-gc-diagnostics'
$publishOwned=$false
$peer=$null;$peerOwned=$false;$profileOwned=$false
$client=$null;$localServer=$null;$tcpProbe=$null;$clrProbe=$null
$neighborPulse=$null;$neighborArguments=@();$pulseResult=$null;$ownedCounts=$null;$peerDhcpEnabled=$null;$clientFailure=$null
$localDataStarted=$false;$remoteDataStarted=$false
$peerAddressPlan=if($RouteVariant -eq 'peer-gateway'){'198.19.240.5,198.19.240.6'}else{'198.19.240.6'}
$receiverState=$null;$receiverEvidence=$null
$pathControls=[Collections.Generic.List[object]]::new()
$routeReport=$null;$cacheReport=$null
$cacheStem=if($RouteRefresh -and $CacheRetirePaths){'cache-control'}else{'route-control'}
$probeStartup=[ordered]@{}
$failure=$null;$cleanupErrors=[Collections.Generic.List[Exception]]::new()
$phase='preflight';$start=$null;$end=$null;$tcpEnd=$null;$result=$null
$port=20300;$count=8192;$heapMiB=1024
$rate=[int][Math]::Ceiling($count/[double]$Seconds)
$analyzer=Join-Path $AnalyzerDirectory 'CpuSamples.exe'
$exe=Join-Path $diagnostics 'ArrivalTcp.exe'
$compiler="$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$wpr="$env:SystemRoot\System32\wpr.exe"
$tcpTrace=Join-Path $diagnostics $(if($WprProbes){'cpu.etl'}else{'tcp.etl'})
$clrTrace=Join-Path $diagnostics $(if($WprProbes){'cpu.etl'}else{'clr.etl'})
function Wait-Ready($Child,[string]$File,[int]$TimeoutSeconds=20) {
    $clock=[Diagnostics.Stopwatch]::StartNew()
    while(-not(Test-Path -LiteralPath $File)) {
        if($Child.Process.HasExited -or $clock.Elapsed.TotalSeconds -gt $TimeoutSeconds){throw 'An owned diagnostic process did not become ready.'}
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
    $phase='analyzer-smoke'
    $null=Invoke-TcpChurnTool -Program $analyzer -Arguments @('--self-test') -Directory $diagnostics `
        -LogPrefix (Join-Path $diagnostics 'analyzer-smoke') -TimeoutSeconds 30
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
    $dataIndex=$route[0].InterfaceIndex
    if($DataInterfaceAlias){
        $ownedData=@(Get-NetAdapter -Name $DataInterfaceAlias -ErrorAction Stop)
        if($ownedData.Count -ne 1 -or [string]$ownedData[0].InterfaceGuid -ne $DataInterfaceGuid){
            throw 'The disposable data interface changed identity.'
        }
        $alias=$DataInterfaceAlias;$dataIndex=$ownedData[0].ifIndex
    }
    $ipInterface=@(Get-NetIPInterface -InterfaceIndex $dataIndex -AddressFamily IPv4)
    if($ipInterface.Count -ne 1 -or $ipInterface[0].NlMtu -lt 1){throw 'A unique client data interface with positive MTU is required.'}
    $mtu=$ipInterface[0].NlMtu
    if($PeerRecovery -or $IsolatedData) {
        $peerData=Invoke-Command -Session $peer -ScriptBlock {
            param($address)
            $ip=@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop|Where-Object IPAddress -eq $address)
            if($ip.Count -ne 1){throw 'A unique owned peer data address is required.'}
            $nic=@(Get-NetAdapter -Name $ip[0].InterfaceAlias -ErrorAction Stop)
            if($nic.Count -ne 1){throw 'A unique owned peer data adapter is required.'}
            $network=@(Get-NetIPInterface -InterfaceIndex $ip[0].InterfaceIndex -AddressFamily IPv4 -ErrorAction Stop)
            if($network.Count -ne 1 -or [string]$network[0].Dhcp -notin @('Enabled','Disabled')){
                throw 'The peer data-interface DHCP state is unavailable.'
            }
            [pscustomobject]@{mac=[string]$nic[0].MacAddress;alias=[string]$nic[0].Name;dhcpEnabled=([string]$network[0].Dhcp -eq 'Enabled')}
        } -ArgumentList $peerAddress
        $peerMac=$peerData.mac;$peerDhcpEnabled=$peerData.dhcpEnabled
    }
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
    $cohortSources=$clientAddress
    $clientSources=@($clientAddress,'127.0.0.1')
    $clientTargets=@($peerAddress,'127.0.0.2')
    if($IsolatedData) {
        $phase='prepare-client-data'
        if([string]$ipInterface[0].Dhcp -ne 'Disabled' -or $peerDhcpEnabled -ne $false){
            throw 'Isolated data aliases require already-static interfaces on both guests.'
        }
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Set-ScopedDataAddresses.ps1') `
            -Destination (Join-Path $remote 'Set-ScopedDataAddresses.ps1') -ToSession $peer
        $cohortSources='198.19.240.1,198.19.240.2,198.19.240.3,198.19.240.4'
        $localDataStarted=$true
        & (Join-Path $PSScriptRoot 'Set-ScopedDataAddresses.ps1') -Action add -InterfaceAlias $alias `
            -Addresses $cohortSources -StateFile (Join-Path $diagnostics 'data-original.clixml') `
            -ReportFile (Join-Path $diagnostics 'data-prepare.json')
        $remoteDataStarted=$true
        $phase='prepare-peer-data'
        Invoke-Command -Session $peer -ScriptBlock {
            param($root,$alias,$addresses)
            & (Join-Path $root 'Set-ScopedDataAddresses.ps1') -Action add -InterfaceAlias $alias `
                -Addresses $addresses -StateFile (Join-Path $root 'data-original.clixml') `
                -ReportFile (Join-Path $root 'data-prepare.json')
        } -ArgumentList $remote,$peerData.alias,$peerAddressPlan
        $clientAddress='198.19.240.1';$peerAddress='198.19.240.6'
        $clientSources=@($cohortSources.Split(','))+@('127.0.0.1','127.0.0.1','127.0.0.1','127.0.0.1')
        $clientTargets=@($peerAddress,$peerAddress,$peerAddress,$peerAddress,'127.0.0.2','127.0.0.2','127.0.0.2','127.0.0.2')
        $phase='resolve-data-neighbor'
        $neighborTargets=@($peerAddress)
        if($RouteVariant -eq 'peer-gateway'){$neighborTargets+='198.19.240.5'}
        $neighborNumber=0
        foreach($neighborTarget in $neighborTargets) {
        try {
            $null=Invoke-TcpChurnTool -Program "$env:SystemRoot\System32\ping.exe" `
                -Arguments @('-n','1','-w','500','-S',$clientAddress,$neighborTarget) -Directory $diagnostics `
                -LogPrefix (Join-Path $diagnostics "data-neighbor-resolution-$neighborNumber") -TimeoutSeconds 10
        }catch [InvalidOperationException] {
            if($_.Exception.Data['ToolExitCode'] -ne 1){throw}
            Write-Verbose 'ICMP echo did not complete; independently verified owned-neighbor resolution is still required.'
        }
        $learned=@(Get-NetNeighbor -InterfaceAlias $alias -AddressFamily IPv4 -PolicyStore ActiveStore|
            Where-Object IPAddress -eq $neighborTarget)
        if($learned.Count -ne 1 -or $learned[0].LinkLayerAddress -ne $peerMac){
            throw 'The isolated data peer did not resolve to its verified owned MAC.'
        }
        $neighborNumber++
        }
    }
    $phase='compile-client'
    $null=Invoke-TcpChurnTool -Program $compiler -Arguments @('/nologo','/target:exe','/platform:x64',"/out:$exe",(Join-Path $sourceRoot 'ArrivalTcp.cs')) `
        -Directory $diagnostics -LogPrefix (Join-Path $diagnostics 'compile')
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'ArrivalTcp.ServerGc.config') -Destination ($exe+'.config')
    $peerOwned=$true
    $phase='start-remote-peer'
    Invoke-Command -Session $peer -ScriptBlock {
        param($root,$listen,$client,$port,$count,$rate,$payloadBytes,$gcRole,$peerPressure,$pressureMinimum)
        if(@(Get-NetIPAddress -AddressFamily IPv4|Where-Object IPAddress -eq $listen).Count -ne 1){throw 'The peer does not uniquely own the declared listen address.'}
        Import-Module (Join-Path $root 'WindowsCts.psm1') -Force
        $global:OwnedManagedGcPeer=@{Process=$null;Rule=$null;Root=$root;PressureServer=$null;PressureClient=$null}
        $compiler="$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
        $exe=Join-Path $root 'ArrivalTcp.exe'
        $null=Invoke-TcpChurnTool -Program $compiler -Arguments @('/nologo','/target:exe','/platform:x64',"/out:$exe",(Join-Path $root 'ArrivalTcp.cs')) `
            -Directory $root -LogPrefix (Join-Path $root 'compile')
        Copy-Item -LiteralPath (Join-Path $root 'ArrivalTcp.ServerGc.config') -Destination ($exe+'.config')
        if($peerPressure){
            if((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory*1024 -lt 4096MB){
                throw 'Insufficient free peer memory for the bounded companion GC workload.'
            }
            $pressureOutput=Join-Path $root 'pressure-server.json'
            $global:OwnedManagedGcPeer.PressureServer=Start-TcpChurnCollector -Program $exe -Arguments @(
                '127.0.0.1','127.0.0.2','20301','4096','819','1048576',$pressureOutput,
                'server','1048576','34711','256','nodelay',("gc:1024:{0}:graph" -f $pressureMinimum)
            ) -Directory $root -LogPrefix (Join-Path $root 'pressure-server')
            $ready=[Diagnostics.Stopwatch]::StartNew()
            while(-not(Test-Path -LiteralPath ($pressureOutput+'.ready'))){
                if($global:OwnedManagedGcPeer.PressureServer.Process.HasExited -or $ready.Elapsed.TotalSeconds -gt 60){
                    throw 'The bounded companion GC receiver did not become ready.'
                }
                Start-Sleep -Milliseconds 50
            }
        }
        if($gcRole -eq 'server'){return}
        $rule='ManagedGcPeer-'+[guid]::NewGuid().ToString('N')
        $null=New-NetFirewallRule -Name $rule -DisplayName $rule -Direction Inbound -Action Allow `
            -Protocol TCP -LocalPort $port -LocalAddress $listen -RemoteAddress ($client -split ',')
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
    } -ArgumentList $remote,$peerAddress,$cohortSources,$port,($count/2),$rate,$payloadBytes,$GcProcessRole,([bool]$PeerGcPressure),$(if($CacheInterfaceAlias){1536}else{1024})
    if($GcProcessRole -eq 'server') {
        $phase='start-profiled-receiver'
        Import-Module (Join-Path $PSScriptRoot 'GcReceiverTraffic.psm1') -Force
        $localOutput=Join-Path $diagnostics 'profiled-server.json'
        $receiverState=@{Peer=$peer;PeerRoot=$remote;Directory=$diagnostics;Executable=$exe
            ServerAddress=$clientAddress;PeerAddress=$peerAddress;Port=$port;Count=$count;Rate=$rate;Payload=$payloadBytes
            Connections=$Connections;HeapMiB=$heapMiB;HeapLayout=$HeapLayout;ReceiveBudgetBytes=$ReceiveBudgetBytes
            PeerGcPressure=([bool]$PeerGcPressure)
            ServerOutput=$localOutput;Rule=$null;Receiver=$null;LocalClient=$null}
        Start-GcReceiver -State $receiverState
        $localServer=$receiverState.Receiver
    } else {
        $localOutput=Join-Path $diagnostics 'loopback.json'
        $phase='start-loopback-peer'
        $localServer=Start-TcpChurnCollector -Program $exe -Arguments @(
            '127.0.0.1','127.0.0.2',[string]$port,[string]($count/2),[string]$rate,[string]$payloadBytes,$localOutput,'server',[string]$payloadBytes,'14529','256','nodelay'
        ) -Directory $diagnostics -LogPrefix (Join-Path $diagnostics 'loopback')
    }
    $receiverReadySeconds=if($GcProcessRole -eq 'server' -and $HeapLayout -eq 'graph'){60}else{20}
    Wait-Ready $localServer ($localOutput+'.ready') $receiverReadySeconds
    $phase='trace-start'
    if(-not $WprProbes){
        $null=Invoke-TcpChurnTool -Program $wpr -Arguments @('-start','CPU','-filemode') -Directory $diagnostics -LogPrefix (Join-Path $diagnostics 'wpr-start')
        $profileOwned=$true
    }
    $phase='tcp-provider-snapshot'
    $provider=Get-WinEvent -ListProvider Microsoft-Windows-TCPIP
    $tasks=@('TcpTcbSynSend','TcpDisconnectTcbRtoTimeout','TcpDataTransferRetransmitRound',
        'TcpBlackHoleDetectionEntry','TcpBlackHoleDetectionExit','TcpBlackHoleDetectionFailed','TcpBhDetectFullSizeAck')
    if($ReceiveBudgetBytes){$tasks+=@('TcpZeroWindowProbingBegin','TcpZeroWindowProbingEnd')}
    if($PeerRecovery){$tasks+=@('TcpConnectTcbComplete','TcpInsertConnectionTuple','TcpCloseTcbRequest')}
    if($GcProcessRole -eq 'server'){$tasks+=@('TcpAcceptListenerComplete','TcpCloseTcbRequest','TcpInsertConnectionTuple')}
    $events=@($provider.Events|Where-Object{$null -ne $_.Task -and $_.Task.Name -in $tasks}|
        ForEach-Object{[pscustomobject]@{Id=$_.Id;Task=$_.Task.Name}})
    foreach($task in $tasks){if($task -notin @($events.Task)){throw 'A required public TCP event is unavailable.'}}
    # Diagnosis, send, connect and TCB events; do not request unrelated rundown/control keywords.
    $tcpKeywords=[long]0x500000084
    foreach($event in @($provider.Events|Where-Object{$null -ne $_.Task -and $_.Task.Name -in $tasks})){
        if(@($event.Keywords).Count -and -not @($event.Keywords|Where-Object{($_.Value -band $tcpKeywords) -ne 0}).Count){
            throw 'The bounded TCP keyword selection does not cover a required public event.'
        }
    }
    $tcpState=Join-Path $diagnostics 'tcp-state.json'
    @{publicProviderGuid=[string]$provider.Id;publicProviderKeywords='0x500000084';publicProviderEvents=$events}|ConvertTo-Json -Depth 4|Set-Content $tcpState
    $clrState=Join-Path $diagnostics 'clr-state.json'
    @{publicProviderGuid='e13c0d23-ccbc-4e12-931b-d9cc2eee27e4';publicProviderKeywords='0x1';publicProviderEvents=@(
        @{Id=1;Task='GCStart'},@{Id=2;Task='GCStop'},@{Id=3;Task='GCRestartEEEnd'},
        @{Id=7;Task='GCRestartEEBegin'},@{Id=8;Task='GCSuspendEEEnd'},@{Id=9;Task='GCSuspendEEBegin'}
    )}|ConvertTo-Json -Depth 4|Set-Content $clrState
    if($WprProbes){
        $phase='wpr-exact-probe-start'
        $wprProfile=Join-Path $diagnostics 'gc-probes.wprp'
        $profileArguments=@{TcpStateFile=$tcpState;ClrStateFile=$clrState;Output=$wprProfile}
        $cpuProfile='CPU'
        if($SpinLocks){
            $kernelProfile=Join-Path $diagnostics 'cpu-spinlocks.wprp'
            $profileArguments.KernelOutput=$kernelProfile;$cpuProfile=$kernelProfile+'!CPU'
        }
        & (Join-Path $PSScriptRoot 'New-GcProbeWprProfile.ps1') @profileArguments
        $null=Invoke-TcpChurnTool -Program $wpr -Arguments @('-start',$cpuProfile,'-start',($wprProfile+'!GcProbeEvents'),'-filemode') `
            -Directory $diagnostics -LogPrefix (Join-Path $diagnostics 'wpr-start')
        $profileOwned=$true
    }else{
    $phase='tcp-probe-start'
    $tcpProbe=Start-TcpChurnCollector -Program $analyzer -Arguments @('--capture-probes',$tcpTrace,
        $tcpState,(Join-Path $diagnostics 'tcp.ready'),(Join-Path $diagnostics 'tcp.stop'),'300') `
        -Directory $diagnostics -LogPrefix (Join-Path $diagnostics 'tcp-capture')
    Wait-Ready $tcpProbe (Join-Path $diagnostics 'tcp.ready')
    $phase='clr-probe-start'
    $clrProbe=Start-TcpChurnCollector -Program $analyzer -Arguments @('--capture-probes',$clrTrace,
        $clrState,(Join-Path $diagnostics 'clr.ready'),(Join-Path $diagnostics 'clr.stop'),'300') `
        -Directory $diagnostics -LogPrefix (Join-Path $diagnostics 'clr-capture')
    Wait-Ready $clrProbe (Join-Path $diagnostics 'clr.ready')
    }
    $before=Get-NetAdapterStatistics -Name $alias
    $start=[DateTime]::UtcNow.ToString('o')
    $phase='managed-gc-traffic'
    $clientOutput=Join-Path $diagnostics 'client.json'
    if($RouteRefresh -or $CacheRetirePaths) {
        $controlTypes=@()
        if($RouteRefresh){$controlTypes+='route'}
        if($CacheRetirePaths){$controlTypes+='cache'}
        foreach($type in $controlTypes){
            $stem=if($type -eq 'cache'){$cacheStem}else{'route-control'}
            $phase=$stem+'-start'
            $program=(Get-Command pwsh -CommandType Application -ErrorAction Stop).Source
            $script=if($type -eq 'cache'){'Invoke-ScopedPathRetirement.ps1'}else{'Invoke-ScopedPathRefresh.ps1'}
            if($type -eq 'route' -and $RouteVariant -eq 'destination-flush'){$script='Invoke-ScopedDestinationCacheFlush.ps1'}
            $controlAlias=if($type -eq 'cache' -and $CacheInterfaceAlias){$CacheInterfaceAlias}else{$alias}
            $arguments=@('-NoProfile','-NonInteractive','-File',(Join-Path $PSScriptRoot $script),
                '-InterfaceAlias',$controlAlias,'-DataStateFile',(Join-Path $diagnostics 'data-original.clixml'),
                '-StateFile',(Join-Path $diagnostics ($stem+'-original.clixml')))
            if($type -eq 'cache'){$arguments+=@('-PathCount',[string]$CacheRetirePaths,
                '-ReceiverExecutable',$exe,'-ReceiverProcessId',[string]$localServer.Process.Id)
                if($CacheInterfaceGuid){$arguments+=@('-UnusedInterfaceGuid',$CacheInterfaceGuid,'-EndFile',($localOutput+'.gc.json'))}
            }
            elseif($RouteVariant -eq 'destination-flush'){
                $arguments+=@('-EndFile',($localOutput+'.gc.json'),'-ReceiverExecutable',$exe,
                    '-ReceiverProcessId',[string]$localServer.Process.Id,'-ExpectedPeerMac',$peerMac)
            }
            else{$arguments+=@('-NextHop',$(if($RouteVariant -eq 'peer-gateway'){'198.19.240.5'}else{'0.0.0.0'}),'-ExpectedPeerMac',$peerMac)}
            $control=[pscustomobject]@{Stem=$stem;Program=$program;Arguments=$arguments;Child=$null}
            $pathControls.Add($control)
            $control.Child=Start-TcpChurnCollector -Program $program -Arguments ($arguments+@(
                '-ReportFile',(Join-Path $diagnostics ($stem+'.json')),'-ReadyFile',(Join-Path $diagnostics ($stem+'.ready')),
                '-BeginFile',($localOutput+'.gc.json.begin'),'-StopFile',(Join-Path $diagnostics ($stem+'.stop'))
            )) -Directory $diagnostics -LogPrefix (Join-Path $diagnostics ($stem+'-agent'))
            Wait-Ready $control.Child (Join-Path $diagnostics ($stem+'.ready')) $(if($type -eq 'cache'){180}else{20})
        }
    }
    if($PeerRecovery) {
        $phase='neighbor-pulse-start'
        $pulseProgram=(Get-Command pwsh -CommandType Application -ErrorAction Stop).Source
        $neighborArguments=@('-NoProfile','-NonInteractive','-File',(Join-Path $PSScriptRoot 'Invoke-ScopedNeighborPulse.ps1'),
            '-InterfaceAlias',$alias,'-LocalAddress',$clientAddress,'-PeerAddress',$peerAddress,'-ExpectedMac',$peerMac,
            '-StateFile',(Join-Path $diagnostics 'neighbor-original.clixml'))
        $neighborPulse=Start-TcpChurnCollector -Program $pulseProgram -Arguments ($neighborArguments+@(
            '-ReportFile',(Join-Path $diagnostics 'neighbor-pulse.json'),'-ReadyFile',(Join-Path $diagnostics 'neighbor.ready'),
            '-TrafficReadyFile',($clientOutput+'.traffic-ready'),'-StopFile',(Join-Path $diagnostics 'neighbor.stop'),
            '-CohortSources',$cohortSources,'-DurationMilliseconds',[string]$RecoveryMilliseconds,
            '-Port',[string]$port)) -Directory $diagnostics -LogPrefix (Join-Path $diagnostics 'neighbor-agent')
        Wait-Ready $neighborPulse (Join-Path $diagnostics 'neighbor.ready')
    }
    $phase='managed-gc-traffic'
    if($GcProcessRole -eq 'server') {
        $clientPid=$localServer.Process.Id
        $r=Invoke-GcReceiverTraffic -State $receiverState
        $end=[DateTime]::UtcNow.ToString('o')
    } else {
    $client=Start-TcpChurnCollector -Program $exe -Arguments @(
        ($clientSources -join ','),($clientTargets -join ','),[string]$port,[string]$count,[string]$rate,[string]$payloadBytes,
        $clientOutput,'client',[string]$payloadBytes,'14529',[string]$Connections,'nodelay',"gc:${heapMiB}:2048:${HeapLayout}"
    ) -Directory $diagnostics -LogPrefix (Join-Path $diagnostics 'client')
    $clientPid=$client.Process.Id
    if(-not $client.Process.WaitForExit(180000)){throw 'The GC client did not complete before its deadline.'}
    $end=[DateTime]::UtcNow.ToString('o')
    if($client.Process.ExitCode -ne 0) {
        if(Test-Path -LiteralPath $clientOutput) {
            $failedClient=Get-Content $clientOutput -Raw|ConvertFrom-Json
            if($failedClient.outcome -eq 'failed'){
                $clientFailure=$failedClient|Select-Object schema,outcome,connectionsStarted,connectionsConnected,connectionsCompleted,acceptedConnections,errorType,errorCode,socketError
            }
        }
        throw 'The GC client did not complete successfully.'
    }
    if($PeerRecovery) {
        $phase='neighbor-pulse-result'
        if(-not $neighborPulse.Process.WaitForExit(15000) -or $neighborPulse.Process.ExitCode -ne 0){throw 'The scoped peer pulse did not complete successfully.'}
        $pulseResult=Get-Content (Join-Path $diagnostics 'neighbor-pulse.json') -Raw|ConvertFrom-Json
        if($pulseResult.outcome -ne 'recovered' -or -not $pulseResult.applied -or -not $pulseResult.restored -or
            $pulseResult.establishedAtTrigger -lt 8 -or $pulseResult.verifiedHoldMilliseconds -lt $RecoveryMilliseconds){
            throw 'The verified established-flow recovery pulse did not cover its requested interval.'
        }
    }
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
    $remoteTargets=@($r.targets|Where-Object{-not $_.loopback})
    $localTargets=@($r.targets|Where-Object loopback)
    if($r.targets.Count -ne $clientTargets.Count -or $remoteTargets.Count -ne $clientTargets.Count/2 -or
        $localTargets.Count -ne $clientTargets.Count/2 -or
        ($remoteTargets|Measure-Object connections -Sum).Sum -ne $remoteResult.connections -or
        ($localTargets|Measure-Object connections -Sum).Sum -ne $l.connections -or
        ($remoteTargets|Measure-Object requestBytes -Sum).Sum -ne $remoteResult.bytesReceived -or
        ($remoteTargets|Measure-Object responseBytes -Sum).Sum -ne $remoteResult.bytesSent -or
        ($localTargets|Measure-Object requestBytes -Sum).Sum -ne $l.bytesReceived -or
        ($localTargets|Measure-Object responseBytes -Sum).Sum -ne $l.bytesSent -or
        -not $r.managedGc.enabled -or $r.managedGc.gen2CollectionsAfter -le $r.managedGc.gen2CollectionsBefore) {
        throw 'Mixed-target byte counts or real managed-GC coverage did not verify.'
    }
    }
    $remoteTargets=@($r.targets|Where-Object{-not $_.loopback})
    $after=Get-NetAdapterStatistics -Name $alias
    if($after.SentBytes-$before.SentBytes -lt ($remoteTargets|Measure-Object requestBytes -Sum).Sum -or
        $after.ReceivedBytes-$before.ReceivedBytes -lt ($remoteTargets|Measure-Object responseBytes -Sum).Sum){throw 'The non-loopback NIC did not account for the remote payload.'}
    $result=[ordered]@{schema=1;workload='managed-gc-mixed';outcome='collected';connections=$r.connections
        bytesSent=$r.bytesSent;bytesReceived=$r.bytesReceived;payloadBytesPerDirection=$payloadBytes
        dataInterfaceMtuBytes=$mtu
        targets=$r.targets;managedGc=$r.managedGc
        arrivalRate=$r.arrivalRate;maxLaunchLagMilliseconds=$r.maxLaunchLagMilliseconds
        arrivalDispatch=$r.arrivalDispatch;meanDispatchQueueMilliseconds=$r.meanDispatchQueueMilliseconds
        maxDispatchQueueMilliseconds=$r.maxDispatchQueueMilliseconds;launchSpanMilliseconds=$r.launchSpanMilliseconds
        workloadMilliseconds=$r.milliseconds;peakInFlight=$r.peakInFlight
        meanBindMilliseconds=$r.meanBindMilliseconds;meanConnectMilliseconds=$r.meanConnectMilliseconds
        cpuCoverage='sampled-etw-only';executionTopology='two-existing-guests-plus-client-loopback'
        targetSeverity='not-evaluated';conclusion='diagnostic-not-customer-severity-proof'}
    $result.isolatedDataAddresses=[bool]$IsolatedData
    $result.profiledProcessRole=$GcProcessRole
    if($PeerGcPressure){
        $pressure=$r.peerGcPressure
        if(-not $CacheInterfaceAlias -and
            (([datetime]$pressure.managedGc.collectionEndUtc).ToUniversalTime() -lt ([datetime]$r.managedGc.collectionStartUtc).ToUniversalTime() -or
            ([datetime]$pressure.managedGc.collectionStartUtc).ToUniversalTime() -gt ([datetime]$r.managedGc.collectionEndUtc).ToUniversalTime())){
            throw 'The independent companion collection did not overlap the profiled real GC.'
        }
        $result.peerGcPressure=$pressure
    }
    $result.probeCollectorBackend=$(if($WprProbes){'wpr-exact-events'}else{'traceevent-exact-events'})
    $result.kernelSpinlockEventsRequested=[bool]$SpinLocks
    if($GcProcessRole -eq 'server'){$result.launchSpanScope='maximum-independent-producer-span';$result.workloadScope='both-independent-producers-plus-profiled-receiver'}
    if($PeerRecovery){$result.peerRecovery=$pulseResult;$result.peerDataInterfaceDhcpEnabled=$peerDhcpEnabled}
}catch{$failure=$_}
finally {
    foreach($name in @('tcp','clr')){
        $startupFile=Join-Path $diagnostics ($name+'.ready.failure.json')
        if(-not(Test-Path -LiteralPath $startupFile)){$startupFile=Join-Path $diagnostics ($name+'.ready.progress.json')}
        if(Test-Path -LiteralPath $startupFile){
            try{
                $probeStartup[$name]=Get-Content -LiteralPath $startupFile -Raw|ConvertFrom-Json|
                    Select-Object schema,outcome,stage,errorType,errorCode
            }catch{$probeStartup[$name]=@{outcome='diagnostic-read-failed';errorType=$_.Exception.GetType().FullName}}
        }
    }
    if($null -ne $receiverState) {
        $receiverEvidence=[ordered]@{stage=$receiverState.Stage;receiver=$null;localProducer=$null;gcObservation=$null;diagnosticErrorType=$null}
        try {
            foreach($entry in @(@{key='receiver';path=$receiverState.ServerOutput},
                @{key='localProducer';path=(Join-Path $diagnostics 'receiver-local-client.json')})) {
                if(Test-Path -LiteralPath $entry.path) {
                    $receiverEvidence[$entry.key]=Get-Content $entry.path -Raw|ConvertFrom-Json|
                        Select-Object schema,outcome,role,connections,connectionsStarted,connectionsConnected,connectionsCompleted,
                            acceptedConnections,errorType,errorCode,socketError,managedGc,requestDispatch,peakInFlight
                }
                if(Test-Path -LiteralPath ($receiverState.ServerOutput+'.gc.json')){
                    $receiverEvidence.gcObservation=Get-Content ($receiverState.ServerOutput+'.gc.json') -Raw|ConvertFrom-Json
                }
            }
        }catch{$receiverEvidence.diagnosticErrorType=$_.Exception.GetType().FullName}
        $client=$receiverState.LocalClient
        $localServer=$receiverState.Receiver
    }
    if($null -ne $neighborPulse) {
        try {
            [IO.File]::WriteAllText((Join-Path $diagnostics 'neighbor.stop'),'stop')
            if(-not $neighborPulse.Process.WaitForExit(30000)){
                $neighborPulse.Process.Kill($true)
                if(-not $neighborPulse.Process.WaitForExit(10000)){throw 'The owned pulse process tree did not terminate.'}
                throw 'The scoped pulse exceeded its graceful restoration deadline.'
            }
        }catch{$cleanupErrors.Add($_.Exception)}
        finally {
            try{Stop-TcpChurnCollector $neighborPulse}catch{$cleanupErrors.Add($_.Exception)}
            if(Test-Path -LiteralPath (Join-Path $diagnostics 'neighbor-original.clixml')) {
                try {
                    $null=Invoke-TcpChurnTool -Program $pulseProgram -Arguments ($neighborArguments+@('-RestoreOnly',
                        '-ReportFile',(Join-Path $diagnostics 'neighbor-restore.json'))) -Directory $diagnostics `
                        -LogPrefix (Join-Path $diagnostics 'neighbor-restore') -TimeoutSeconds 30
                }catch{$cleanupErrors.Add($_.Exception)}
            }
        }
    }
    foreach($child in @($client,$localServer)){if($null -ne $child){try{Stop-TcpChurnCollector $child}catch{$cleanupErrors.Add($_.Exception)}}}
    if($null -eq $end -and $null -ne $receiverState){$end=[DateTime]::UtcNow.ToString('o')}
    if($null -ne $receiverState -and $receiverState.Rule){
        try{Remove-NetFirewallRule -Name $receiverState.Rule -ErrorAction Stop}catch{$cleanupErrors.Add($_.Exception)}
    }
    $tcpEnd=[DateTime]::UtcNow.ToString('o')
    foreach($control in $pathControls) {
        try {
            [IO.File]::WriteAllText((Join-Path $diagnostics ($control.Stem+'.stop')),'stop')
            if($null -ne $control.Child -and -not $control.Child.Process.WaitForExit(30000)){
                $control.Child.Process.Kill($true)
                if(-not $control.Child.Process.WaitForExit(10000)){throw 'The owned path-control process tree did not terminate.'}
                throw 'The route-control agent exceeded its bounded restoration deadline.'
            }
        }catch{$cleanupErrors.Add($_.Exception)}
        finally {
            if($null -ne $control.Child){try{Stop-TcpChurnCollector $control.Child}catch{$cleanupErrors.Add($_.Exception)}}
            if(Test-Path -LiteralPath (Join-Path $diagnostics ($control.Stem+'-original.clixml'))) {
                try {
                    $null=Invoke-TcpChurnTool -Program $control.Program -Arguments ($control.Arguments+@('-RestoreOnly',
                        '-ReportFile',(Join-Path $diagnostics ($control.Stem+'-restored.json')))) -Directory $diagnostics `
                        -LogPrefix (Join-Path $diagnostics ($control.Stem+'-restore')) -TimeoutSeconds 30
                }catch{$cleanupErrors.Add($_.Exception)}
            }
        }
    }
    foreach($entry in @(@{child=$tcpProbe;stop='tcp.stop'},@{child=$clrProbe;stop='clr.stop'})) {
        if($null -eq $entry.child){continue}
        try {
            [IO.File]::WriteAllText((Join-Path $diagnostics $entry.stop),'stop')
            if(-not $entry.child.Process.WaitForExit(20000) -or $entry.child.Process.ExitCode -ne 0){throw 'An owned probe did not close cleanly.'}
        }catch{$cleanupErrors.Add($_.Exception)}
        finally{try{Stop-TcpChurnCollector $entry.child}catch{$cleanupErrors.Add($_.Exception)}}
    }
    if($profileOwned) {
        $stopArguments=@('-stop',(Join-Path $diagnostics 'cpu.etl'))
        if($WprProbes){$stopArguments+='-skipPdbGen'}
        try {$null=Invoke-TcpChurnTool -Program $wpr -Arguments $stopArguments `
            -Directory $diagnostics -LogPrefix (Join-Path $diagnostics 'wpr-stop') -TimeoutSeconds 120}
        catch{$cleanupErrors.Add($_.Exception)}
    }
    if($peerOwned -and $null -ne $peer) {
        try {Invoke-Command -Session $peer -ScriptBlock {
            $errors=[Collections.Generic.List[Exception]]::new()
            foreach($child in @($global:OwnedManagedGcPeer.Process,$global:OwnedManagedGcPeer.PressureClient,$global:OwnedManagedGcPeer.PressureServer)){
                if($null -ne $child){
                    try{Stop-TcpChurnCollector $child}catch{$errors.Add($_.Exception)}
                }
            }
            if($global:OwnedManagedGcPeer.Rule){
                try{Remove-NetFirewallRule -Name $global:OwnedManagedGcPeer.Rule -ErrorAction Stop}catch{$errors.Add($_.Exception)}
            }
            if($errors.Count){throw [AggregateException]::new('Owned peer workload cleanup failed.',$errors)}
        }}catch{$cleanupErrors.Add($_.Exception)}
    }
    if($remoteDataStarted -and $null -ne $peer) {
        try {Invoke-Command -Session $peer -ScriptBlock {
            param($root,$alias,$addresses)
            if(Test-Path -LiteralPath (Join-Path $root 'data-original.clixml')) {
                & (Join-Path $root 'Set-ScopedDataAddresses.ps1') -Action remove -InterfaceAlias $alias `
                    -Addresses $addresses -StateFile (Join-Path $root 'data-original.clixml') `
                    -ReportFile (Join-Path $root 'data-restored.json')
            }
        } -ArgumentList $remote,$peerData.alias,$peerAddressPlan}catch{$cleanupErrors.Add($_.Exception)}
    }
    if($localDataStarted -and (Test-Path -LiteralPath (Join-Path $diagnostics 'data-original.clixml'))) {
        try {
            & (Join-Path $PSScriptRoot 'Set-ScopedDataAddresses.ps1') -Action remove -InterfaceAlias $alias `
                -Addresses $cohortSources -StateFile (Join-Path $diagnostics 'data-original.clixml') `
                -ReportFile (Join-Path $diagnostics 'data-restored.json')
        }catch{$cleanupErrors.Add($_.Exception)}
    }
    if($null -ne $peer){try{Remove-PSSession $peer -ErrorAction Stop}catch{$cleanupErrors.Add($_.Exception)}}
}
if($null -ne $failure -or $cleanupErrors.Count) {
    $diagnosticVerified=$false;$diagnosticFailure=$null
    if(($null -ne $clientFailure -or $null -ne $receiverState) -and $profileOwned -and
        (Test-Path -LiteralPath (Join-Path $diagnostics 'cpu.etl'))) {
        try {
            $null=Invoke-TcpChurnTool -Program $analyzer -Arguments @((Join-Path $diagnostics 'cpu.etl'),
                (Join-Path $PublishDirectory 'cpu-load.json'),$start,$end) -Directory $diagnostics `
                -LogPrefix (Join-Path $diagnostics 'failed-workload-cpu') -TimeoutSeconds 300
            $null=Invoke-TcpChurnTool -Program $analyzer -Arguments @('--events',$tcpTrace,
                (Join-Path $PublishDirectory 'tcp-events.json'),'interval',$start,$tcpEnd,(Join-Path $diagnostics 'tcp-state.json')) `
                -Directory $diagnostics -LogPrefix (Join-Path $diagnostics 'failed-workload-tcp') -TimeoutSeconds 120
            $cpu=Get-Content (Join-Path $PublishDirectory 'cpu-load.json') -Raw|ConvertFrom-Json
            $tcp=Get-Content (Join-Path $PublishDirectory 'tcp-events.json') -Raw|ConvertFrom-Json
            if($cpu.outcome -ne 'sampled' -or $cpu.eventsLost -ne 0 -or $cpu.unresolvedNetworkFrames -ne 0 -or
                $tcp.outcome -ne 'counted' -or $tcp.eventsLost -ne 0){
                throw 'The rejected-workload diagnostic did not verify lossless matching CPU/TCP coverage.'
            }
            if($PeerRecovery -and $clientFailure.connectionsConnected -gt 0) {
                Import-Module (Join-Path $PSScriptRoot 'TcpRecoveryEvidence.psm1') -Force
                $ownedCounts=Read-TcpRecoveryEvidence -Provider $provider -TracePath $tcpTrace `
                    -StartUtc ([datetime]$start) -EndUtc ([datetime]$tcpEnd) -OwnerProcessId $clientPid `
                    -ExpectedConnections $clientFailure.connectionsConnected
            }
            $diagnosticVerified=$true
            if($null -ne $receiverEvidence -and $null -ne $receiverEvidence.gcObservation) {
                $postStart=([datetime]$receiverEvidence.gcObservation.collectionEndUtc).ToUniversalTime()
                $endUtc=([datetime]$end).ToUniversalTime()
                $postEnd=if($postStart.AddSeconds(2) -lt $endUtc){$postStart.AddSeconds(2)}else{$endUtc}
                if($postEnd -gt $postStart) {
                    $null=Invoke-TcpChurnTool -Program $analyzer -Arguments @((Join-Path $diagnostics 'cpu.etl'),
                        (Join-Path $PublishDirectory 'cpu-after-gc.json'),$postStart.ToString('o'),$postEnd.ToString('o')) `
                        -Directory $diagnostics -LogPrefix (Join-Path $diagnostics 'failed-receiver-post-gc') -TimeoutSeconds 300
                    $postCpu=Get-Content (Join-Path $PublishDirectory 'cpu-after-gc.json') -Raw|ConvertFrom-Json
                    if($postCpu.outcome -ne 'sampled' -or $postCpu.eventsLost -ne 0 -or $postCpu.unresolvedNetworkFrames -ne 0){
                        throw 'The rejected receiver post-GC diagnostic did not verify.'
                    }
                }
            }
        }catch{$diagnosticFailure=$_}
    }
    if($publishOwned) {
        if($PeerRecovery -and (Test-Path -LiteralPath (Join-Path $diagnostics 'neighbor-pulse.json'))) {
            $pulseResult=Get-Content (Join-Path $diagnostics 'neighbor-pulse.json') -Raw|ConvertFrom-Json
        }
        if($RouteRefresh -and (Test-Path -LiteralPath (Join-Path $diagnostics 'route-control.json'))){
            $routeReport=Get-Content (Join-Path $diagnostics 'route-control.json') -Raw|ConvertFrom-Json
        }
        if($CacheRetirePaths -and (Test-Path -LiteralPath (Join-Path $diagnostics ($cacheStem+'.json')))){
            $cacheReport=Get-Content (Join-Path $diagnostics ($cacheStem+'.json')) -Raw|ConvertFrom-Json
        }
        $type=if($null -ne $failure){$failure.Exception.GetType().FullName}else{'cleanup-failure'}
        $code=if($null -ne $failure){$failure.Exception.HResult}else{$null}
        $toolCode=if($null -ne $failure -and $failure.Exception.Data.Contains('ToolExitCode')){$failure.Exception.Data['ToolExitCode']}else{$null}
        @{schema=1;workload='managed-gc-mixed';outcome='failed';phase=$phase;failureType=$type;failureCode=$code
            failureSourceLine=$(if($null -ne $failure){$failure.InvocationInfo.ScriptLineNumber}else{$null})
            probeStartup=$probeStartup
            toolExitCode=$toolCode;cleanupErrorCount=$cleanupErrors.Count;cleanupVerified=($cleanupErrors.Count -eq 0)
            cleanupErrorTypes=@($cleanupErrors|ForEach-Object{$_.GetType().FullName})
            peerRecovery=$pulseResult;peerDataInterfaceDhcpEnabled=$peerDhcpEnabled;clientFailure=$clientFailure
            receiverEvidence=$receiverEvidence
            routeRefreshControl=$(if($RouteRefresh){$routeReport}else{$null})
            cacheRetirementControl=$cacheReport
            tcpRecovery=$ownedCounts
            rejectedWorkloadCpuTcpVerified=$diagnosticVerified
            diagnosticFailureType=$(if($null -ne $diagnosticFailure){$diagnosticFailure.Exception.GetType().FullName}else{$null})
            conclusion='no-accepted-measurement'}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $PublishDirectory 'result.json')
    }
    if($null -ne $failure){$cleanupErrors.Insert(0,$failure.Exception)}
    if($null -ne $diagnosticFailure){$cleanupErrors.Add($diagnosticFailure.Exception)}
    throw [AggregateException]::new('Managed-GC diagnostic or required cleanup failed.',$cleanupErrors)
}
$phase='public-symbol-analysis'
try {
    if($CacheRetirePaths){
        $phase='verify-cache-retirement'
        $cacheReport=Get-Content (Join-Path $diagnostics ($cacheStem+'.json')) -Raw|ConvertFrom-Json
        if($cacheReport.outcome -ne 'completed' -or -not $cacheReport.retired -or -not $cacheReport.restored -or
            -not $cacheReport.dataAndManagementAddressesPreserved -or -not $cacheReport.defaultRoutesPreserved -or
            $cacheReport.measuredReleasedPaths -lt $CacheRetirePaths -or $cacheReport.establishedAtSnapshot -lt 8 -or
            ([datetime]$cacheReport.removeApiStartUtc).ToUniversalTime() -lt ([datetime]$start).ToUniversalTime() -or
            ([datetime]$cacheReport.removeApiEndUtc).ToUniversalTime() -gt ([datetime]$end).ToUniversalTime()){
            throw 'The bounded source-retirement population, live cohort, timing or restoration did not verify.'
        }
        if($CacheInterfaceGuid -and
            ($cacheReport.triggerPhase -ne 'gc-complete-pre-released-cache' -or
                ([datetime]$cacheReport.snapshotCompletedUtc).ToUniversalTime() -lt ([datetime]$r.managedGc.collectionStartUtc).ToUniversalTime() -or
                ([datetime]$cacheReport.snapshotCompletedUtc).ToUniversalTime() -gt ([datetime]$r.managedGc.collectionEndUtc).ToUniversalTime() -or
                ([datetime]$cacheReport.removeApiStartUtc).ToUniversalTime() -lt ([datetime]$r.managedGc.collectionEndUtc).ToUniversalTime())){
            throw 'The unused-interface snapshot did not complete during GC or the writer began before GC completed.'
        }
        $result.cacheRetirementControl=$cacheReport
    }
    if($RouteRefresh) {
        $phase='verify-route-control'
        $routeReport=Get-Content (Join-Path $diagnostics 'route-control.json') -Raw|ConvertFrom-Json
        if($RouteVariant -eq 'destination-flush'){
            if($routeReport.outcome -ne 'completed' -or $routeReport.scenario -ne 'owned-destination-cache-flush' -or
                $routeReport.destinationFlushes -ne 2 -or -not $routeReport.networkConfigurationPreserved -or
                -not $routeReport.peerMacVerified -or $routeReport.establishedAtSnapshot -lt 8 -or
                ([datetime]$routeReport.snapshotCompletedUtc).ToUniversalTime() -lt ([datetime]$r.managedGc.collectionStartUtc).ToUniversalTime() -or
                ([datetime]$routeReport.snapshotCompletedUtc).ToUniversalTime() -gt ([datetime]$r.managedGc.collectionEndUtc).ToUniversalTime() -or
                ([datetime]$routeReport.applyStartUtc).ToUniversalTime() -lt ([datetime]$r.managedGc.collectionEndUtc).ToUniversalTime() -or
                ([datetime]$routeReport.applyEndUtc).ToUniversalTime() -gt ([datetime]$end).ToUniversalTime()){
                throw 'The exact owned-destination flush, live cohort, GC phase or unchanged network configuration did not verify.'
            }
        }elseif($routeReport.outcome -ne 'completed' -or -not $routeReport.added -or -not $routeReport.removed -or
            -not $routeReport.sameInterface -or -not $routeReport.defaultRoutesPreserved -or
            ($RouteVariant -eq 'onlink' -and -not $routeReport.sameInterfaceAndNextHop) -or
            ($RouteVariant -eq 'peer-gateway' -and (-not $routeReport.peerMacVerified -or $routeReport.nextHopKind -ne 'owned-peer-gateway')) -or
            ([datetime]$routeReport.addedUtc).ToUniversalTime() -lt ([datetime]$start).ToUniversalTime() -or
            ([datetime]$routeReport.addedUtc).ToUniversalTime() -gt ([datetime]$end).ToUniversalTime()){
            throw 'The owned route control did not apply within the workload and restore unchanged default routing.'
        }
        $result.routeRefreshControl=$routeReport
    }
    $phase='analyze-whole-cpu'
    $null=Invoke-TcpChurnTool -Program $analyzer -Arguments @((Join-Path $diagnostics 'cpu.etl'),
        (Join-Path $PublishDirectory 'cpu-load.json'),$start,$end) -Directory $diagnostics `
        -LogPrefix (Join-Path $diagnostics 'cpu-analysis') -TimeoutSeconds 300
    if($SpinLocks){
        $phase='analyze-owned-spinlock-evidence'
        $null=Invoke-TcpChurnTool -Program $analyzer -Arguments @('--spin-summary',(Join-Path $diagnostics 'cpu.etl'),
            (Join-Path $PublishDirectory 'lock-evidence.json'),$start,$end) -Directory $diagnostics `
            -LogPrefix (Join-Path $diagnostics 'spinlock-evidence') -TimeoutSeconds 300
    }
    $postStart=([datetime]$r.managedGc.collectionEndUtc).ToUniversalTime()
    $endUtc=([datetime]$end).ToUniversalTime()
    $postEnd=if($postStart.AddSeconds(2) -lt $endUtc){$postStart.AddSeconds(2)}else{$endUtc}
    if($postEnd -le $postStart){throw 'No positive post-collection window remains.'}
    $phase='analyze-post-gc-cpu'
    $null=Invoke-TcpChurnTool -Program $analyzer -Arguments @((Join-Path $diagnostics 'cpu.etl'),
        (Join-Path $PublishDirectory 'cpu-after-gc.json'),$postStart.ToString('o'),$postEnd.ToString('o')) `
        -Directory $diagnostics -LogPrefix (Join-Path $diagnostics 'post-gc-analysis') -TimeoutSeconds 300
    $phase='analyze-tcp-events'
    $tcpCoverageEnd=if($PeerRecovery -or $GcProcessRole -eq 'server'){$tcpEnd}else{$end}
    $null=Invoke-TcpChurnTool -Program $analyzer -Arguments @('--events',$tcpTrace,
        (Join-Path $PublishDirectory 'tcp-events.json'),'interval',$start,$tcpCoverageEnd,(Join-Path $diagnostics 'tcp-state.json')) `
        -Directory $diagnostics -LogPrefix (Join-Path $diagnostics 'tcp-analysis') -TimeoutSeconds 120
    $tcpSummary=Get-Content (Join-Path $PublishDirectory 'tcp-events.json') -Raw|ConvertFrom-Json
    if($tcpSummary.outcome -ne 'counted' -or $tcpSummary.eventsLost -ne 0){throw 'Lossless TCP event coverage is required.'}
    $cpuFiles=@('cpu-load.json','cpu-after-gc.json')
    if($PeerRecovery -or $GcProcessRole -eq 'server') {
        $phase='verify-recovery-coverage'
        Import-Module (Join-Path $PSScriptRoot 'TcpRecoveryEvidence.psm1') -Force
        $ownerEvent=if($GcProcessRole -eq 'server'){'TcpAcceptListenerComplete'}else{'TcpConnectTcbComplete'}
        $ownedCounts=Read-TcpRecoveryEvidence -Provider $provider -TracePath $tcpTrace `
            -StartUtc ([datetime]$start) -EndUtc ([datetime]$tcpCoverageEnd) -OwnerProcessId $clientPid -ExpectedConnections $count -OwnerEventKind $ownerEvent
        $result.tcpRecovery=$ownedCounts
    }
    if($PeerRecovery) {
        $recoveryStart=([datetime]$pulseResult.restoredUtc).ToUniversalTime()
        $recoveryEnd=if($recoveryStart.AddSeconds(2) -lt $endUtc){$recoveryStart.AddSeconds(2)}else{$endUtc}
        if($recoveryEnd -le $recoveryStart){throw 'No positive post-recovery CPU window remains.'}
        $phase='analyze-post-recovery-cpu'
        $null=Invoke-TcpChurnTool -Program $analyzer -Arguments @((Join-Path $diagnostics 'cpu.etl'),
            (Join-Path $PublishDirectory 'cpu-after-recovery.json'),$recoveryStart.ToString('o'),$recoveryEnd.ToString('o')) `
            -Directory $diagnostics -LogPrefix (Join-Path $diagnostics 'recovery-cpu-analysis') -TimeoutSeconds 300
        $cpuFiles+='cpu-after-recovery.json'
    }
    $phase='analyze-clr-events'
    $null=Invoke-TcpChurnTool -Program $analyzer -Arguments @('--events',$clrTrace,
        (Join-Path $diagnostics 'clr-loss.json'),[string]$clientPid,$start,$end,(Join-Path $diagnostics 'clr-state.json')) `
        -Directory $diagnostics -LogPrefix (Join-Path $diagnostics 'clr-loss-analysis') -TimeoutSeconds 120
    $clrSummary=Get-Content (Join-Path $diagnostics 'clr-loss.json') -Raw|ConvertFrom-Json
    if($clrSummary.outcome -ne 'counted' -or $clrSummary.eventsLost -ne 0 -or -not $clrSummary.processFilterApplied){
        throw 'Lossless owned-process CLR event coverage is required.'
    }
    if($clrSummary.providerEventsInInterval -lt 1 -or $clrSummary.providerEventsInInterval -gt 1024){
        throw 'Owned-process CLR event coverage is missing or exceeds its bound.'
    }
    $gcCounts=@{}
    foreach($event in (Get-Content -LiteralPath $clrState -Raw|ConvertFrom-Json).publicProviderEvents){
        $counted=[long]$clrSummary.publicProbeCounts.($event.Task)
        if($counted -gt 0){$gcCounts[[string]$event.Id]=$counted}
    }
    if(-not $gcCounts.ContainsKey('8') -or -not $gcCounts.ContainsKey('7')){throw 'CLR suspension/restart events did not verify.'}
    @{schema=1;processFilterApplied=$true;eventCounts=$gcCounts;eventsLost=0;scope='owned-profiled-process-workload-interval';
        conclusion='event-coverage-not-exact-pause-correlation'}|ConvertTo-Json -Depth 4|Set-Content (Join-Path $PublishDirectory 'clr-events.json')
    foreach($file in $cpuFiles) {
        $cpu=Get-Content (Join-Path $PublishDirectory $file) -Raw|ConvertFrom-Json
        if($cpu.outcome -ne 'sampled' -or $cpu.eventsLost -ne 0 -or $cpu.unresolvedNetworkFrames -ne 0){throw 'Lossless matching public-symbol CPU attribution is required.'}
    }
    if($PeerRecovery -and ($ownedCounts.publicProbeCounts.TcpDataTransferRetransmitRound -lt 1 -or
        $ownedCounts.publicProbeCounts.TcpBlackHoleDetectionEntry -lt 1)) {
        $phase='verify-recovery-coverage'
        throw 'The recovery experiment did not verify data retransmission and actual BH entry.'
    }
    if($PeerGcPressure -and $CacheInterfaceAlias){
        $phase='verify-maintenance-pressure-overlap'
        $pressure=$r.peerGcPressure
        if(([datetime]$pressure.managedGc.collectionEndUtc).ToUniversalTime() -lt ([datetime]$cacheReport.removeApiStartUtc).ToUniversalTime() -or
            ([datetime]$pressure.managedGc.collectionStartUtc).ToUniversalTime() -gt ([datetime]$cacheReport.removeApiEndUtc).ToUniversalTime()){
            throw 'The independent companion collection did not overlap the unused-interface cleanup API.'
        }
        $result.peerGcPressure|Add-Member NoteProperty overlapTarget 'unused-interface-cleanup-api' -Force
    }
    $result.cleanupVerified=$true
    $result|ConvertTo-Json -Depth 6|Set-Content (Join-Path $PublishDirectory 'result.json')
}catch {
    $toolCode=if($_.Exception.Data.Contains('ToolExitCode')){$_.Exception.Data['ToolExitCode']}else{$null}
    @{schema=1;workload='managed-gc-mixed';outcome='failed';phase=$phase;failureType=$_.Exception.GetType().FullName
        failureCode=$_.Exception.HResult;toolExitCode=$toolCode;cleanupVerified=$true
        peerRecovery=$pulseResult;tcpRecovery=$ownedCounts;peerDataInterfaceDhcpEnabled=$peerDhcpEnabled
        routeRefreshControl=$(if($RouteRefresh){$routeReport}else{$null})
        cacheRetirementControl=$cacheReport
        managedGc=$r.managedGc;peerGcPressure=$r.peerGcPressure;connections=$r.connections
        conclusion='analysis-not-accepted'}|
        ConvertTo-Json -Depth 6|Set-Content (Join-Path $PublishDirectory 'result.json')
    throw
}
