# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
param([string]$Compiler="$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe")
$ErrorActionPreference='Stop'
$directory=Join-Path ([IO.Path]::GetTempPath()) ('gc-arrival-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $directory
$exe=Join-Path $directory 'ArrivalTcp.exe'
$clientOutput=Join-Path $directory 'client.json'
$serverOutput=Join-Path $directory 'server.json'
$client=$null;$server=$null;$checks=0
$multiServers=[Collections.Generic.List[object]]::new()
function Start-Workload([string[]]$Arguments) {
    $info=[Diagnostics.ProcessStartInfo]::new()
    $info.FileName=$exe;$info.UseShellExecute=$false;$info.RedirectStandardError=$true
    foreach($argument in $Arguments){$info.ArgumentList.Add($argument)}
    $process=[Diagnostics.Process]::Start($info)
    @{process=$process;error=$process.StandardError.ReadToEndAsync()}
}
function Close-Owned($Child) {
    if(-not $Child.process.HasExited){Stop-Process -Id $Child.process.Id -Force -ErrorAction Stop}
    if(-not $Child.process.WaitForExit(5000)){throw 'An owned GC workload process remained.'}
    $Child.process.Dispose()
}
try {
    & $Compiler /nologo /target:exe /platform:x64 "/out:$exe" (Join-Path $PSScriptRoot 'ArrivalTcp.cs')
    if($LASTEXITCODE){throw 'GC arrival helper compilation failed.'}
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'ArrivalTcp.ServerGc.config') -Destination ($exe+'.config')
    $probe=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Parse('127.0.0.2'),0)
    $probe.Start();$port=$probe.LocalEndpoint.Port;$probe.Stop()
    $common=@('127.0.0.1','127.0.0.2',[string]$port,'128','4000','65536')
    $server=Start-Workload ($common+@($serverOutput,'server','262144','14529','64','nodelay'))
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while(-not(Test-Path -LiteralPath ($serverOutput+'.ready'))) {
        if($server.process.HasExited -or $watch.Elapsed.TotalSeconds -gt 10){
            throw 'The separate GC-test server did not become ready.'
        }
        Start-Sleep -Milliseconds 20
    }
    $client=Start-Workload ($common+@($clientOutput,'client','262144','14529','64','nodelay','gc:32:32'))
    if(-not $client.process.WaitForExit(30000)){throw 'The GC arrival client exceeded its functional-test deadline.'}
    if($client.process.ExitCode -ne 0){throw "GC client failed: $($client.error.GetAwaiter().GetResult())"}
    if(-not $server.process.WaitForExit(5000) -or $server.process.ExitCode -ne 0){throw 'The GC-test server did not complete.'}
    $r=Get-Content -LiteralPath $clientOutput -Raw|ConvertFrom-Json
    $s=Get-Content -LiteralPath $serverOutput -Raw|ConvertFrom-Json
    if($r.connections -ne 128 -or $r.bytesSent -ne 8388608 -or $r.bytesReceived -ne 33554432 -or
        $r.bytesSent -ne $s.bytesReceived -or $r.bytesReceived -ne $s.bytesSent -or
        $r.networkErrors -ne 0 -or $r.protocolErrors -ne 0 -or $r.barrier -or -not $r.noDelay) {
        throw 'GC request/reply integrity, pacing or no-barrier contract failed.'
    }
    $checks++
    if(-not(Test-Path -LiteralPath ($clientOutput+'.traffic-ready')) -or
        $r.arrivalDispatch -ne 'thread-pool' -or $null -eq $r.meanDispatchQueueMilliseconds -or
        $null -eq $r.maxDispatchQueueMilliseconds -or $r.meanDispatchQueueMilliseconds -lt 0 -or
        $r.maxDispatchQueueMilliseconds -lt $r.meanDispatchQueueMilliseconds -or
        $r.managedGc.startedBeforeCollection -lt $r.managedGc.completedBeforeCollection -or
        $r.managedGc.startedBeforeCollection -gt $r.managedGc.launchedAtCollection) {
        throw 'Bounded GC dispatch timing or actual-start accounting failed.'
    }
    $checks++
    $gc=$r.managedGc
    if(-not $gc.enabled -or $gc.heapMiB -ne 32 -or $gc.launchedAtCollection -lt 32 -or
        $gc.completedBeforeCollection -lt 1 -or $gc.inFlightBeforeCollection -lt 1 -or
        $gc.gen2CollectionsAfter -le $gc.gen2CollectionsBefore -or
        $gc.blockingCollectionMilliseconds -le 0 -or -not $gc.serverGc -or
        ([datetime]$gc.collectionEndUtc) -lt ([datetime]$gc.collectionStartUtc)) {
        throw "A real blocking generation-2 collection did not overlap completed and in-flight requests: $($gc|ConvertTo-Json -Compress)"
    }
    $checks++
    Close-Owned $client;$client=$null
    Close-Owned $server;$server=$null
    foreach($index in 0..1) {
        $peer="127.0.0.$(2+$index)"
        $result=Join-Path $directory "multi-server-$index.json"
        $targetCount=if($index -eq 0){65}else{64}
        $child=Start-Workload @('127.0.0.1',$peer,[string]$port,[string]$targetCount,'4000','1048576',$result,'server','1048576','14529','64','nodelay')
        $multiServers.Add($child);$watch.Restart()
        while(-not(Test-Path -LiteralPath ($result+'.ready'))) {
            if($child.process.HasExited -or $watch.Elapsed.TotalSeconds -gt 10){throw 'A mixed-target listener did not become ready.'}
            Start-Sleep -Milliseconds 20
        }
    }
    $multiOutput=Join-Path $directory 'multi-client.json'
    $client=Start-Workload @('127.0.0.1,127.0.0.4','127.0.0.2,127.0.0.3',[string]$port,'129','4000','1048576',
        $multiOutput,'client','1048576','14529','64','nodelay','gc:32:32')
    if(-not $client.process.WaitForExit(30000) -or $client.process.ExitCode -ne 0){throw 'The mixed-target GC client failed.'}
    foreach($child in $multiServers){if(-not $child.process.WaitForExit(5000) -or $child.process.ExitCode -ne 0){throw 'A mixed-target server failed.'}}
    $mixed=Get-Content -LiteralPath $multiOutput -Raw|ConvertFrom-Json
    if($mixed.connections -ne 129 -or $mixed.bytesSent -ne 129MB -or $mixed.bytesReceived -ne 129MB -or
        $mixed.targets.Count -ne 2 -or
        $mixed.targets[0].connections -ne 65 -or $mixed.targets[1].connections -ne 64 -or
        @($mixed.targets|Where-Object{-not $_.loopback}).Count -or
        ($mixed.targets|Measure-Object requestBytes -Sum).Sum -ne $mixed.bytesSent -or
        ($mixed.targets|Measure-Object responseBytes -Sum).Sum -ne $mixed.bytesReceived -or -not $mixed.managedGc.enabled) {
        throw 'Mixed-target GC delivery/accounting failed.'
    }
    $checks++
    foreach($index in 0..1) {
        $peerResult=Get-Content -LiteralPath (Join-Path $directory "multi-server-$index.json") -Raw|ConvertFrom-Json
        if($peerResult.connections -ne $mixed.targets[$index].connections -or $peerResult.bytesReceived -ne $mixed.targets[$index].requestBytes -or
            $peerResult.bytesSent -ne $mixed.targets[$index].responseBytes){throw 'A mixed target received the wrong request allocation.'}
    }
    $checks++
    Close-Owned $client;$client=$null
    foreach($child in $multiServers){Close-Owned $child};$multiServers.Clear()
    foreach($index in 0..1) {
        $peer="127.0.0.$(2+$index)"
        $result=Join-Path $directory "eight-server-$index.json"
        $targetCount=if($index -eq 0){65}else{64}
        $child=Start-Workload @('127.0.0.1',$peer,[string]$port,[string]$targetCount,'4000','1048576',$result,'server','1048576','14529','64','nodelay')
        $multiServers.Add($child);$watch.Restart()
        while(-not(Test-Path -LiteralPath ($result+'.ready'))) {
            if($child.process.HasExited -or $watch.Elapsed.TotalSeconds -gt 10){throw 'An eight-target fixture listener did not become ready.'}
            Start-Sleep -Milliseconds 20
        }
    }
    $eightOutput=Join-Path $directory 'eight-client.json'
    $eightSources=(1..8|ForEach-Object{"127.0.1.$_"}) -join ','
    $eightPeers=(@('127.0.0.2','127.0.0.2','127.0.0.2','127.0.0.2','127.0.0.3','127.0.0.3','127.0.0.3','127.0.0.3') -join ',')
    $client=Start-Workload @($eightSources,$eightPeers,[string]$port,'129','4000','1048576',
        $eightOutput,'client','1048576','14529','64','nodelay','gc:32:32')
    if(-not $client.process.WaitForExit(30000) -or $client.process.ExitCode -ne 0){throw 'Eight-target GC request delivery failed.'}
    foreach($child in $multiServers){if(-not $child.process.WaitForExit(5000) -or $child.process.ExitCode -ne 0){throw 'An eight-target fixture server failed.'}}
    $eight=Get-Content $eightOutput -Raw|ConvertFrom-Json
    if($eight.targets.Count -ne 8 -or $eight.bytesSent -ne 129MB -or $eight.bytesReceived -ne 129MB -or
        ($eight.targets[0..3]|Measure-Object connections -Sum).Sum -ne 65 -or
        ($eight.targets[4..7]|Measure-Object connections -Sum).Sum -ne 64){
        throw 'Eight-target duplicate-peer allocation or byte accounting failed.'
    }
    foreach($index in 0..1) {
        $observed=Get-Content (Join-Path $directory "eight-server-$index.json") -Raw|ConvertFrom-Json
        $members=if($index -eq 0){$eight.targets[0..3]}else{$eight.targets[4..7]}
        if($observed.connections -ne ($members|Measure-Object connections -Sum).Sum -or
            $observed.bytesReceived -ne ($members|Measure-Object requestBytes -Sum).Sum -or
            $observed.bytesSent -ne ($members|Measure-Object responseBytes -Sum).Sum){
            throw 'Eight-target endpoint verification failed.'
        }
    }
    $checks++
    Close-Owned $client;$client=$null
    foreach($child in $multiServers){Close-Owned $child};$multiServers.Clear()
    foreach($case in @('zero-heap','oversize-heap','late-trigger','server-role','invalid-pacing','misaligned-peers')) {
        $mode=switch($case){zero-heap {'gc:0:32'} oversize-heap {'gc:1025:32'} late-trigger {'gc:32:128'} default {'gc:32:32'}}
        $role=if($case -eq 'server-role'){'server'}else{'client'}
        $pacing=if($case -eq 'invalid-pacing'){'invalid'}else{'nodelay'}
        $arguments=@($common)
        if($case -eq 'misaligned-peers'){$arguments[1]='127.0.0.2,127.0.0.3'}
        $client=Start-Workload ($arguments+@((Join-Path $directory "$case.json"),$role,'262144','14529','64',$pacing,$mode))
        if(-not $client.process.WaitForExit(5000) -or $client.process.ExitCode -eq 0 -or
            [string]::IsNullOrWhiteSpace($client.error.GetAwaiter().GetResult())){throw "Invalid GC case accepted or not diagnosed: $case"}
        Close-Owned $client;$client=$null;$checks++
    }
    $failureOutput=Join-Path $directory 'refused-client.json'
    $client=Start-Workload @('127.0.0.1','127.0.0.2',[string]$port,'1','1','1',
        $failureOutput,'client','1','14529','1','nodelay')
    if(-not $client.process.WaitForExit(5000) -or $client.process.ExitCode -eq 0){throw 'The closed-listener failure test did not fail promptly.'}
    $failed=Get-Content $failureOutput -Raw|ConvertFrom-Json
    if($failed.outcome -ne 'failed' -or $failed.connectionsStarted -ne 1 -or $failed.connectionsConnected -ne 0 -or
        $failed.connectionsCompleted -ne 0 -or $failed.socketError -ne 10061 -or $failed.errorType -ne 'System.Net.Sockets.SocketException'){
        throw 'A real connection failure was not reported explicitly with sanitized numeric evidence.'
    }
    Close-Owned $client;$client=$null;$checks++
} finally {
    foreach($child in @($client,$server)){if($null -ne $child){Close-Owned $child}}
    foreach($child in $multiServers){Close-Owned $child}
    foreach($file in @($exe,($exe+'.config'),$clientOutput,($clientOutput+'.traffic-ready'),$serverOutput,($serverOutput+'.ready'))) {
        if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file -ErrorAction Stop}
    }
    foreach($file in @('multi-client.json','multi-client.json.traffic-ready','multi-server-0.json','multi-server-0.json.ready','multi-server-1.json','multi-server-1.json.ready')) {
        $path=Join-Path $directory $file
        if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -ErrorAction Stop}
    }
    foreach($file in @('eight-client.json','eight-client.json.traffic-ready','eight-server-0.json','eight-server-0.json.ready','eight-server-1.json','eight-server-1.json.ready')) {
        $path=Join-Path $directory $file
        if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -ErrorAction Stop}
    }
    $failedPath=Join-Path $directory 'refused-client.json'
    if(Test-Path -LiteralPath $failedPath){Remove-Item -LiteralPath $failedPath -ErrorAction Stop}
    Remove-Item -LiteralPath $directory -ErrorAction Stop
}
Write-Output "Passed $checks managed-GC arrival cases; loopback checks are functional coverage, not kernel-contention evidence."
