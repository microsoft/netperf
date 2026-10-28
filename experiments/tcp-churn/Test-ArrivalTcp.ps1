# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
[CmdletBinding()]
param([string]$Compiler="$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe")
$ErrorActionPreference='Stop'
$directory=Join-Path ([IO.Path]::GetTempPath()) ('arrival-test-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $directory
$exe=Join-Path $directory 'ArrivalTcp.exe'
$output=Join-Path $directory 'result.json'
$child=$null;$server=$null;$checks=0
try {
    & $Compiler /nologo /target:exe /platform:x64 "/out:$exe" (Join-Path $PSScriptRoot 'ArrivalTcp.cs')
    if($LASTEXITCODE){throw 'Arrival helper compilation failed.'}
    $probe=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Parse('127.0.0.2'),0)
    $probe.Start();$port=$probe.LocalEndpoint.Port;$probe.Stop()
    foreach($case in @('valid','existing-output','oversize-count','excess-duration','missing-arguments')) {
        $count=if($case -eq 'oversize-count'){8193}else{16}
        $rate=if($case -eq 'excess-duration'){1}else{128}
        if($case -eq 'excess-duration'){$count=8192}
        $info=[Diagnostics.ProcessStartInfo]::new()
        $info.FileName=$exe;$info.UseShellExecute=$false;$info.RedirectStandardError=$true
        foreach($argument in @('127.0.0.1','127.0.0.2',[string]$port,[string]$count,[string]$rate,'65536',$output)) {
            $info.ArgumentList.Add($argument)
        }
        if($case -eq 'missing-arguments'){$info.ArgumentList.Clear()}
        $child=[Diagnostics.Process]::Start($info)
        $errorText=$child.StandardError.ReadToEndAsync()
        if(-not $child.WaitForExit(10000)){throw 'Arrival test exceeded its deadline.'}
        if(($child.ExitCode -eq 0) -ne ($case -eq 'valid')){throw "Incorrect arrival outcome: ${case}: $($errorText.GetAwaiter().GetResult())"}
        if($case -eq 'missing-arguments' -and ($child.ExitCode -ne 2 -or
            $errorText.GetAwaiter().GetResult() -notmatch '^Usage: ArrivalTcp ')){throw 'Missing arrival arguments did not produce explicit usage.'}
        if($case -eq 'valid') {
            $result=Get-Content -LiteralPath $output -Raw|ConvertFrom-Json
            if($result.connections -ne 16 -or $result.bytesSent -ne 1048576 -or $result.networkErrors -ne 0 -or
                $result.protocolErrors -ne 0 -or $result.barrier -or $result.seed -ne 14529 -or
                $result.launchSpanMilliseconds -le 0 -or $result.meanLaunchLagMilliseconds -lt 0) {
                throw 'Independent-arrival payload, timing or no-barrier contract failed.'
            }
        }
        $child.Dispose();$child=$null;$checks++
    }
    $serverOutput=Join-Path $directory 'server.json'
    $clientOutput=Join-Path $directory 'client.json'
    $info.ArgumentList.Clear()
    foreach($argument in @('127.0.0.1','127.0.0.2',[string]$port,'16','128','1024',$serverOutput,'server','65536','14529','128','nodelay')) {
        $info.ArgumentList.Add($argument)
    }
    $server=[Diagnostics.Process]::Start($info)
    $serverError=$server.StandardError.ReadToEndAsync()
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while(-not(Test-Path -LiteralPath ($serverOutput+'.ready'))) {
        if($server.HasExited -or $watch.Elapsed.TotalSeconds -gt 5){throw 'Separate server did not become ready.'}
        Start-Sleep -Milliseconds 20
    }
    $probeMethod=[Reflection.Assembly]::Load([IO.File]::ReadAllBytes($exe)).GetType('ArrivalTcp').GetMethod('IsListenerReady')
    if(-not $probeMethod.Invoke($null,@([int]$server.Id,[int]$port)) -or
        $probeMethod.Invoke($null,@([int]$PID,[int]$port))){throw 'Listener readiness did not verify socket ownership.'}
    $info.ArgumentList.Clear()
    foreach($argument in @('127.0.0.1','127.0.0.2',[string]$port,'16','128','1024',$clientOutput,'client','65536','12345','128','nodelay')) {
        $info.ArgumentList.Add($argument)
    }
    $child=[Diagnostics.Process]::Start($info)
    $clientError=$child.StandardError.ReadToEndAsync()
    if(-not $child.WaitForExit(10000) -or $child.ExitCode -ne 0 -or
        -not $server.WaitForExit(5000) -or $server.ExitCode -ne 0){throw 'Separate client/server request exchange failed.'}
    $clientResult=Get-Content $clientOutput -Raw|ConvertFrom-Json
    $serverResult=Get-Content $serverOutput -Raw|ConvertFrom-Json
    if($clientResult.role -ne 'client' -or $serverResult.role -ne 'server' -or
        $clientResult.connections -ne 16 -or $serverResult.connections -ne 16 -or
        $clientResult.bytesSent -ne $serverResult.bytesReceived -or $clientResult.bytesReceived -ne $serverResult.bytesSent -or
        $serverResult.bytesSent -ne 1048576 -or $clientResult.bytesSent -ne 16384 -or
        $clientResult.seed -ne 12345 -or $clientResult.peakInFlight -gt $clientResult.maximumInFlight -or
        $clientResult.meanRequestMilliseconds -le 0 -or -not $clientResult.noDelay -or
        $clientResult.maximumInFlight -ne 128){throw 'Independent endpoint byte/count/seed/latency verification failed.'}
    $checks++
    if($probeMethod.Invoke($null,@([int]$server.Id,[int]$port))){throw 'An exited listener was reported ready.'}
    $checks++
} finally {
    if($null -ne $child) {
        if(-not $child.HasExited){Stop-Process -Id $child.Id -Force -ErrorAction Stop}
        if(-not $child.WaitForExit(5000)){throw 'Owned arrival process did not terminate.'}
        $child.Dispose()
    }
    if($null -ne $server) {
        if(-not $server.HasExited){Stop-Process -Id $server.Id -Force -ErrorAction Stop}
        if(-not $server.WaitForExit(5000)){throw 'Owned arrival server did not terminate.'}
        $server.Dispose()
    }
    foreach($path in @($output,$exe,(Join-Path $directory 'server.json'),(Join-Path $directory 'server.json.ready'),
        (Join-Path $directory 'client.json'))){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -ErrorAction Stop}}
    Remove-Item -LiteralPath $directory -ErrorAction Stop
}
Write-Output "Passed $checks independent-arrival cases; loopback checks are not performance evidence."
