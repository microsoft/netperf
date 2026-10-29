# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
param([ValidateSet('arrays','graph')][string]$HeapLayout='arrays',
    [ValidateSet(0,16384)][int]$ReceiveBudgetBytes=0,
    [ValidateSet(1,64)][int]$ExchangesPerConnection=1,
    [ValidateRange(1,4096)][int]$MaximumInFlight=64,
    [switch]$LargeStreaming,
    [switch]$FramedNagle,
    [switch]$CoreClr,
    [switch]$IdleKeepalive)
$ErrorActionPreference='Stop'
$directory=Join-Path ([IO.Path]::GetTempPath()) ('server-gc-arrival-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $directory
$exe=Join-Path $directory 'ArrivalTcp.exe'
$children=[Collections.Generic.List[object]]::new()
function Start-Child([string[]]$Arguments) {
    if($CoreClr){
        $owned=Start-TcpChurnCollector -Program $exe -Arguments $Arguments -Directory $directory `
            -LogPrefix (Join-Path $directory ('core-child-'+$children.Count)) -CoreClr
        $child=@{process=$owned.Process;error=$owned.Error}
        $children.Add($child)
        return $child
    }
    $info=[Diagnostics.ProcessStartInfo]::new()
    $info.FileName=$exe;$info.UseShellExecute=$false;$info.RedirectStandardError=$true
    foreach($argument in $Arguments){$info.ArgumentList.Add($argument)}
    $process=[Diagnostics.Process]::Start($info)
    $child=@{process=$process;error=$process.StandardError.ReadToEndAsync()}
    $children.Add($child)
    $child
}
try {
    & "$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:exe /platform:x64 "/out:$exe" (Join-Path $PSScriptRoot 'ArrivalTcp.cs')
    if($LASTEXITCODE){throw 'Server-GC helper compilation failed.'}
    Copy-Item (Join-Path $PSScriptRoot 'ArrivalTcp.ServerGc.config') ($exe+'.config')
    if($CoreClr){
        Import-Module (Join-Path $PSScriptRoot 'adapters\WindowsCts.psm1') -Force
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'adapters\Invoke-ArrivalTcpCore.ps1') -Destination $directory
    }
    $probe=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Parse('127.0.0.2'),0)
    $probe.Start();$port=$probe.LocalEndpoint.Port;$probe.Stop()
    $serverOutput=Join-Path $directory 'server.json'
    $descriptor="gc:32:32:{0}" -f $HeapLayout
    if($ReceiveBudgetBytes){$descriptor+=':'+$ReceiveBudgetBytes}
    if($LargeStreaming -and $ExchangesPerConnection -ne 1){throw 'Large streaming is separate from small-message persistent mode.'}
    if($FramedNagle -and $ExchangesPerConnection -ne 64){throw 'Framed Nagle mode requires persistent64 exchanges.'}
    if($IdleKeepalive -and ($ExchangesPerConnection -ne 1 -or $LargeStreaming)){throw 'Idle keepalive mode requires one bounded small exchange.'}
    $requestBytes=if($LargeStreaming){1048576}elseif($ExchangesPerConnection -eq 64 -or $IdleKeepalive){1460}else{65536}
    $responseBytes=if($LargeStreaming){1048576}elseif($ExchangesPerConnection -eq 64 -or $IdleKeepalive){1460}else{262144}
    $repeatOption=if($ExchangesPerConnection -eq 64){@($(if($FramedNagle){'exchanges:64:framed'}else{'exchanges:64'}))}else{@()}
    if($IdleKeepalive){$repeatOption=@('idlekeepalive')}
    $pacing=if($FramedNagle){'nagle'}else{'nodelay'}
    $server=Start-Child (@('127.0.0.1','127.0.0.2',[string]$port,'128','4000',[string]$requestBytes,
        $serverOutput,'server',[string]$responseBytes,'14529',[string]$MaximumInFlight,$pacing,$descriptor)+$repeatOption)
    $wait=[Diagnostics.Stopwatch]::StartNew()
    while(-not(Test-Path ($serverOutput+'.ready'))) {
        if($server.process.HasExited -or $wait.Elapsed.TotalSeconds -gt 15){throw 'The GC receiver did not become ready.'}
        Start-Sleep -Milliseconds 20
    }
    $first=Start-Child (@('127.0.0.1','127.0.0.2',[string]$port,'64','2000',[string]$requestBytes,
        (Join-Path $directory 'first.json'),'client',[string]$responseBytes,'14529',[string]$MaximumInFlight,$pacing,'dispatch:pool')+$repeatOption)
    $second=Start-Child (@('127.0.0.4','127.0.0.2',[string]$port,'64','2000',[string]$requestBytes,
        (Join-Path $directory 'second.json'),'client',[string]$responseBytes,'23521',[string]$MaximumInFlight,$pacing,'dispatch:pool')+$repeatOption)
    foreach($child in @($first,$second,$server)) {
        if(-not $child.process.WaitForExit($(if($FramedNagle -or $IdleKeepalive){120000}else{30000}))){throw 'An independent server-GC endpoint exceeded its deadline.'}
        if($child.process.ExitCode -ne 0){throw "An independent server-GC endpoint failed: $($child.error.GetAwaiter().GetResult())"}
    }
    $r=Get-Content $serverOutput -Raw|ConvertFrom-Json
    $a=Get-Content (Join-Path $directory 'first.json') -Raw|ConvertFrom-Json
    $b=Get-Content (Join-Path $directory 'second.json') -Raw|ConvertFrom-Json
    foreach($client in @($a,$b)) {
        if($IdleKeepalive -and ($client.keepaliveIdleMillisecondsRequested -ne 1000 -or
            $client.keepaliveIntervalMillisecondsRequested -ne 1000 -or $client.idleHoldMinimumMilliseconds -ne 8000 -or
            $client.idleHoldMaximumMilliseconds -ne 30000)){throw 'Idle lifetime/settings were not reported at their explicit bounds.'}
        if($client.outcome -ne 'collected' -or $client.connections -ne 64 -or
            $client.exchangesPerConnection -ne $ExchangesPerConnection -or
            $client.framedWrites -ne [bool]$FramedNagle -or $client.noDelay -ne (-not [bool]$FramedNagle) -or
            $client.managedCoreLibrary -ne $(if($CoreClr){'System.Private.CoreLib'}else{'mscorlib'}) -or
            $client.idleKeepalive -ne [bool]$IdleKeepalive -or $client.keepaliveConfiguredSockets -ne $(if($IdleKeepalive){64}else{0}) -or
            $client.maximumPerConnectionReadBufferBytes -ne [Math]::Min($responseBytes,65536) -or
            $client.bytesSent -ne 64*$requestBytes*$ExchangesPerConnection -or
            $client.bytesReceived -ne 64*$responseBytes*$ExchangesPerConnection -or
            $client.managedGc.enabled -or $client.arrivalDispatch -ne 'thread-pool' -or $client.barrier){
            throw 'An independent arrival producer was paused, corrupted data, or used a barrier.'
        }
    }
    if($r.outcome -ne 'collected' -or $r.connections -ne 128 -or $r.exchangesPerConnection -ne $ExchangesPerConnection -or
        $r.framedWrites -ne [bool]$FramedNagle -or $r.noDelay -ne (-not [bool]$FramedNagle) -or
        $r.managedCoreLibrary -ne $(if($CoreClr){'System.Private.CoreLib'}else{'mscorlib'}) -or
        $r.idleKeepalive -ne [bool]$IdleKeepalive -or $r.keepaliveConfiguredSockets -ne $(if($IdleKeepalive){128}else{0}) -or
        $r.bytesReceived -ne $a.bytesSent+$b.bytesSent -or
        $r.bytesSent -ne $a.bytesReceived+$b.bytesReceived -or $r.requestDispatch -ne 'thread-pool' -or
        $r.maximumPerConnectionReadBufferBytes -ne [Math]::Min($requestBytes,65536) -or
        $r.peakInFlight -lt 1 -or $r.peakInFlight -gt $MaximumInFlight -or $r.barrier){
        throw 'Receiver dispatch, capacity, or endpoint byte accounting failed.'
    }
    $gc=$r.managedGc
    if($gc.configuredReceiveBudgetBytes -ne $ReceiveBudgetBytes -or $gc.maximumPostedReadBytes -ne $ReceiveBudgetBytes -or
        $gc.observedMaximumPostedReadBytes -ne [Math]::Min($ReceiveBudgetBytes,$requestBytes)){
        throw 'Receiver socket/read budgets did not verify.'
    }
    if($gc.requestedListenBacklogHint -ne $(if($ReceiveBudgetBytes){8192}else{0})){
        throw 'The receiver backlog hint did not verify.'
    }
    $observed=Get-Content ($serverOutput+'.gc.json') -Raw|ConvertFrom-Json
    if((Get-Content ($serverOutput+'.gc.json.begin') -Raw) -ne 'pre-collection-call' -or
        $observed.heapLayout -ne $HeapLayout -or $observed.collectionEndUtc -ne $gc.collectionEndUtc -or
        $observed.blockingCollectionMilliseconds -ne $gc.blockingCollectionMilliseconds){
        throw 'Independent GC observation did not match the final receiver result.'
    }
    if(-not $gc.enabled -or -not $gc.serverGc -or $gc.heapMiB -ne 32 -or $gc.heapLayout -ne $HeapLayout -or
        $gc.gen2CollectionsAfter -le $gc.gen2CollectionsBefore -or $gc.blockingCollectionMilliseconds -le 0 -or
        $gc.completedBeforeCollection -lt 1 -or $gc.inFlightBeforeCollection -lt 1 -or $gc.launchedAtCollection -lt 32){
        throw 'A real receiver GC did not overlap completed and in-flight requests.'
    }
}finally {
    foreach($child in $children) {
        if(-not $child.process.HasExited){Stop-Process -Id $child.process.Id -Force -ErrorAction Stop}
        if(-not $child.process.WaitForExit(5000)){throw 'An owned server-GC endpoint remained.'}
        $child.process.Dispose()
    }
    foreach($file in @('ArrivalTcp.exe','ArrivalTcp.exe.config','Invoke-ArrivalTcpCore.ps1','server.json','server.json.ready','server.json.gc.json','server.json.gc.json.begin','first.json','second.json')) {
        $path=Join-Path $directory $file
        if(Test-Path $path){Remove-Item -LiteralPath $path -ErrorAction Stop}
    }
    Remove-Item -LiteralPath $directory -ErrorAction Stop
}
Write-Output 'Passed independent-producer receiver-GC integrity, bounded dispatch and real-GC overlap checks; not performance evidence.'
