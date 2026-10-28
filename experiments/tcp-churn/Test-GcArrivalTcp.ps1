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
        $child=Start-Workload @('127.0.0.1',$peer,[string]$port,[string]$targetCount,'4000','65536',$result,'server','262144','14529','64','nodelay')
        $multiServers.Add($child);$watch.Restart()
        while(-not(Test-Path -LiteralPath ($result+'.ready'))) {
            if($child.process.HasExited -or $watch.Elapsed.TotalSeconds -gt 10){throw 'A mixed-target listener did not become ready.'}
            Start-Sleep -Milliseconds 20
        }
    }
    $multiOutput=Join-Path $directory 'multi-client.json'
    $client=Start-Workload @('127.0.0.1,127.0.0.4','127.0.0.2,127.0.0.3',[string]$port,'129','4000','65536',
        $multiOutput,'client','262144','14529','64','nodelay','gc:32:32')
    if(-not $client.process.WaitForExit(30000) -or $client.process.ExitCode -ne 0){throw 'The mixed-target GC client failed.'}
    foreach($child in $multiServers){if(-not $child.process.WaitForExit(5000) -or $child.process.ExitCode -ne 0){throw 'A mixed-target server failed.'}}
    $mixed=Get-Content -LiteralPath $multiOutput -Raw|ConvertFrom-Json
    if($mixed.connections -ne 129 -or $mixed.targets.Count -ne 2 -or
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
} finally {
    foreach($child in @($client,$server)){if($null -ne $child){Close-Owned $child}}
    foreach($child in $multiServers){Close-Owned $child}
    foreach($file in @($exe,($exe+'.config'),$clientOutput,$serverOutput,($serverOutput+'.ready'))) {
        if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file -ErrorAction Stop}
    }
    foreach($file in @('multi-client.json','multi-server-0.json','multi-server-0.json.ready','multi-server-1.json','multi-server-1.json.ready')) {
        $path=Join-Path $directory $file
        if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -ErrorAction Stop}
    }
    Remove-Item -LiteralPath $directory -ErrorAction Stop
}
Write-Output "Passed $checks managed-GC arrival cases; loopback checks are functional coverage, not kernel-contention evidence."
