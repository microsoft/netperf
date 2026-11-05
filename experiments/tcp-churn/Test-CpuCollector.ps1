# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
[CmdletBinding()]
param([string]$Compiler="$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe")
$ErrorActionPreference='Stop'
$directory=Join-Path ([IO.Path]::GetTempPath()) ('cpu-test-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $directory
$exe=Join-Path $directory 'CpuUtilization.exe'
$output=Join-Path $directory 'cpu.json';$ready=Join-Path $directory 'ready';$stop=Join-Path $directory 'stop'
$child=$null;$checks=0
try {
    & $Compiler /nologo /target:exe /platform:x64 "/out:$exe" (Join-Path $PSScriptRoot 'CpuUtilization.cs')
    if($LASTEXITCODE){throw 'CPU collector compile failed.'}
    $info=[Diagnostics.ProcessStartInfo]::new()
    $info.FileName=$exe;$info.UseShellExecute=$false;$info.RedirectStandardError=$true
    foreach($arg in @($output,$ready,$stop,'10','1000')){$info.ArgumentList.Add($arg)}
    $child=[Diagnostics.Process]::Start($info)
    $stderr=$child.StandardError.ReadToEndAsync()
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while(-not(Test-Path -LiteralPath $ready)) {
        if($child.HasExited -or $watch.Elapsed.TotalSeconds -gt 5){throw "CPU collector not ready: $($stderr.GetAwaiter().GetResult())"}
        Start-Sleep -Milliseconds 20
    }
    Start-Sleep -Milliseconds 2200
    [IO.File]::WriteAllText($stop,'stop')
    if(-not $child.WaitForExit(5000) -or $child.ExitCode -ne 0){throw "CPU collector failed owned shutdown: $($stderr.GetAwaiter().GetResult())"}
    $capture=Get-Content $output -Raw|ConvertFrom-Json
    if($capture.outcome -ne 'collected' -or -not $capture.instances.Count -or $capture.intervals.Count -lt 2 -or
        $capture.requestedIntervalMilliseconds -ne 1000 -or $capture.snapshot -ne 'coherent-pdh-query' -or
        $capture.timestampSource -ne 'Utc-bracketed-PdhCollectQueryDataWithTime' -or
        $capture.maximumQueryMilliseconds -gt 100 -or
        (([datetime]$capture.intervals[-1].endUtc)-[DateTime]::UtcNow).Duration().TotalSeconds -gt 5){
        throw 'CPU collector did not produce completed group-aware interval data.'
    }
    foreach($row in $capture.intervals) {
        if($row.percentBusy.Count -ne $capture.instances.Count -or
            @($row.percentBusy|Where-Object{-not [double]::IsFinite($_)}).Count){throw 'Invalid CPU vector.'}
    }
    $checks++
    $child.Dispose();$child=$null
    $child=[Diagnostics.Process]::Start($info)
    $stderr=$child.StandardError.ReadToEndAsync()
    if(-not $child.WaitForExit(5000) -or $child.ExitCode -eq 0){throw 'CPU collector accepted reused control/output files.'}
    $checks++
    $child.Dispose();$child=$null
    $info.ArgumentList.Clear()
    $child=[Diagnostics.Process]::Start($info)
    $stderr=$child.StandardError.ReadToEndAsync()
    if(-not $child.WaitForExit(5000) -or $child.ExitCode -ne 2 -or
        $stderr.GetAwaiter().GetResult() -notmatch '^Usage: CpuUtilization '){throw 'Missing arguments did not produce explicit CPU collector usage.'}
    $checks++
} finally {
    if($null -ne $child) {
        if(-not $child.HasExited){Stop-Process -Id $child.Id -Force -ErrorAction Stop}
        if(-not $child.WaitForExit(5000)){throw 'Owned CPU collector process remained.'}
        $child.Dispose()
    }
    foreach($path in @($output,$ready,$stop,$exe)){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -ErrorAction Stop}}
    Remove-Item -LiteralPath $directory -ErrorAction Stop
}
Write-Output "Passed $checks CPU collector lifecycle cases."
