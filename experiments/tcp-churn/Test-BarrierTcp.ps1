# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
[CmdletBinding()]
param([string]$Compiler="$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe")
$ErrorActionPreference='Stop'
if(-not (Test-Path -LiteralPath $Compiler -PathType Leaf)) { throw 'The .NET Framework C# compiler is required.' }
$directory=Join-Path ([IO.Path]::GetTempPath()) ('barrier-test-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $directory
$exe=Join-Path $directory 'BarrierTcp.exe'
$child=$null;$checks=0
try {
    & $Compiler /nologo /target:exe /platform:x64 "/out:$exe" (Join-Path $PSScriptRoot 'BarrierTcp.cs')
    if($LASTEXITCODE) { throw 'Barrier helper compilation failed.' }
    $probe=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Parse('127.0.0.2'),0)
    $probe.Start();$port=$probe.LocalEndpoint.Port;$probe.Stop()
    $info=[Diagnostics.ProcessStartInfo]::new()
    $info.FileName=$exe;$info.UseShellExecute=$false
    foreach($arg in @('127.0.0.1','127.0.0.2',[string]$port,'16','65536',$directory)) { $info.ArgumentList.Add($arg) }
    $child=[Diagnostics.Process]::Start($info)
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while(-not (Test-Path -LiteralPath (Join-Path $directory 'ready'))) {
        if($child.HasExited -or $watch.Elapsed.TotalSeconds -gt 15) { throw 'Test connections did not reach the barrier.' }
        Start-Sleep -Milliseconds 20
    }
    if((Get-Content (Join-Path $directory 'ready')) -ne '16' -or
        (Test-Path (Join-Path $directory 'done')) -or (Test-Path (Join-Path $directory 'result.json'))) {
        throw 'Data transferred before the first-data release barrier.'
    }
    $checks++
    [IO.File]::WriteAllText((Join-Path $directory 'go'),'go')
    while(-not (Test-Path -LiteralPath (Join-Path $directory 'done'))) {
        if($child.HasExited -or $watch.Elapsed.TotalSeconds -gt 20) { throw 'Barrier transfer did not complete.' }
        Start-Sleep -Milliseconds 20
    }
    $result=Get-Content (Join-Path $directory 'result.json') -Raw|ConvertFrom-Json
    if($result.connections -ne 16 -or $result.bytesSent -ne 1048576 -or $result.networkErrors -ne 0 -or
        $result.protocolErrors -ne 0 -or $child.HasExited) { throw 'Payload verification or post-transfer hold failed.' }
    $checks++
    [IO.File]::WriteAllText((Join-Path $directory 'stop'),'stop')
    if(-not $child.WaitForExit(5000) -or $child.ExitCode -ne 0) { throw 'Owned barrier connections did not close cleanly.' }
    $child.Dispose();$child=$null
    foreach($count in @(16,8193)) {
        $info.ArgumentList.Clear()
        foreach($arg in @('127.0.0.1','127.0.0.2',[string]$port,[string]$count,'65536',$directory)) { $info.ArgumentList.Add($arg) }
        $info.RedirectStandardError=$true
        $child=[Diagnostics.Process]::Start($info)
        $errorText=$child.StandardError.ReadToEndAsync()
        if(-not $child.WaitForExit(5000) -or $child.ExitCode -eq 0) { throw 'Invalid barrier configuration was accepted or hung.' }
        $child.Dispose();$child=$null;$checks++
    }
} finally {
    if($null -ne $child) {
        if(-not $child.HasExited) { Stop-Process -Id $child.Id -Force -ErrorAction Stop }
        if(-not $child.WaitForExit(5000)) { throw 'Owned barrier test process did not terminate.' }
        $child.Dispose()
    }
    foreach($file in @('BarrierTcp.exe','ready','go','done','stop','result.json')) {
        $path=Join-Path $directory $file
        if(Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -ErrorAction Stop }
    }
    Remove-Item -LiteralPath $directory -ErrorAction Stop
}
Write-Output "Passed $checks first-data barrier cases; loopback checks are not performance evidence."
