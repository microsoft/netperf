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
$child=$null;$checks=0
try {
    & $Compiler /nologo /target:exe /platform:x64 "/out:$exe" (Join-Path $PSScriptRoot 'ArrivalTcp.cs')
    if($LASTEXITCODE){throw 'Arrival helper compilation failed.'}
    $probe=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Parse('127.0.0.2'),0)
    $probe.Start();$port=$probe.LocalEndpoint.Port;$probe.Stop()
    foreach($case in @('valid','existing-output','oversize-count','excess-duration')) {
        $count=if($case -eq 'oversize-count'){8193}else{16}
        $rate=if($case -eq 'excess-duration'){1}else{128}
        if($case -eq 'excess-duration'){$count=8192}
        $info=[Diagnostics.ProcessStartInfo]::new()
        $info.FileName=$exe;$info.UseShellExecute=$false;$info.RedirectStandardError=$true
        foreach($argument in @('127.0.0.1','127.0.0.2',[string]$port,[string]$count,[string]$rate,'65536',$output)) {
            $info.ArgumentList.Add($argument)
        }
        $child=[Diagnostics.Process]::Start($info)
        $errorText=$child.StandardError.ReadToEndAsync()
        if(-not $child.WaitForExit(10000)){throw 'Arrival test exceeded its deadline.'}
        if(($child.ExitCode -eq 0) -ne ($case -eq 'valid')){throw "Incorrect arrival outcome: $case."}
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
} finally {
    if($null -ne $child) {
        if(-not $child.HasExited){Stop-Process -Id $child.Id -Force -ErrorAction Stop}
        if(-not $child.WaitForExit(5000)){throw 'Owned arrival process did not terminate.'}
        $child.Dispose()
    }
    foreach($path in @($output,$exe)){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -ErrorAction Stop}}
    Remove-Item -LiteralPath $directory -ErrorAction Stop
}
Write-Output "Passed $checks independent-arrival cases; loopback checks are not performance evidence."
