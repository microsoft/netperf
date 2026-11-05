# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'CpuUtilization.psm1') -Force
$start=[DateTime]::Parse('2026-01-01T00:00:00Z').ToUniversalTime()
$capture=[pscustomobject]@{outcome='collected';snapshot='coherent-pdh-query';timestampSource='Utc-bracketed-PdhCollectQueryDataWithTime'
    maximumQueryMilliseconds=1;instances=@('0,0','1,0');intervals=@(
    [pscustomobject]@{startUtc=$start.ToString('o');endUtc=$start.AddSeconds(1).ToString('o');percentBusy=@(100,0)}
    [pscustomobject]@{startUtc=$start.AddSeconds(1).ToString('o');endUtc=$start.AddSeconds(3).ToString('o');percentBusy=@(100,100)}
)}
$r=Measure-LogicalProcessorUtilization -Capture $capture -StartUtc $start -EndUtc $start.AddSeconds(3)
if([Math]::Abs($r.averageBusyCpuEquivalents-5.0/3) -gt 0.00001 -or $r.busyCpuSeconds -ne 5 -or
    $r.peakProcessorsAtLeast90Percent -ne 2){throw 'Time-weighted CPU integration failed.'}
$checks=1
$r=Measure-LogicalProcessorUtilization -Capture $capture -StartUtc $start.AddSeconds(1) -EndUtc $start.AddSeconds(2)
if($r.averageBusyCpuEquivalents -ne 2 -or $r.coveredSeconds -ne 1){throw 'Measurement-window clipping failed.'}
$checks++
$typed=[pscustomobject]@{outcome='collected';snapshot='coherent-pdh-query';timestampSource='Utc-bracketed-PdhCollectQueryDataWithTime'
    maximumQueryMilliseconds=1;instances=@('0,0');intervals=@(
    [pscustomobject]@{startUtc=$start.AddMilliseconds(125);endUtc=$start.AddMilliseconds(875);percentBusy=@(100)}
)}
$r=Measure-LogicalProcessorUtilization -Capture $typed -StartUtc $start.AddMilliseconds(250) -EndUtc $start.AddMilliseconds(750)
if($r.coveredSeconds -ne 0.5 -or $r.busyCpuSeconds -ne 0.5){throw 'Typed JSON timestamps lost subsecond precision.'}
$checks++
foreach($case in @('loss-of-coverage','bad-value','duplicate-instance','incomplete','overlap','sequential-counter-vector','unverified-provider-clock',
    'null-value','boolean-value','text-value','null-query-bound','text-query-bound')) {
    $data=$capture|ConvertTo-Json -Depth 5|ConvertFrom-Json
    switch($case) {
        loss-of-coverage {$data.intervals=@($data.intervals[0])}
        bad-value {$data.intervals[0].percentBusy[0]=200}
        duplicate-instance {$data.instances[1]='0,0'}
        incomplete {$data.outcome='deadline'}
        overlap {$data.intervals[1].startUtc=$start.ToString('o')}
        sequential-counter-vector {$data.snapshot='sequential-counter-reads'}
        unverified-provider-clock {$data.timestampSource='PdhCollectQueryDataWithTime'}
        null-value {$data.intervals[0].percentBusy[0]=$null}
        boolean-value {$data.intervals[0].percentBusy[0]=$true}
        text-value {$data.intervals[0].percentBusy[0]='100'}
        null-query-bound {$data.maximumQueryMilliseconds=$null}
        text-query-bound {$data.maximumQueryMilliseconds='1'}
    }
    $rejected=$false
    try{$null=Measure-LogicalProcessorUtilization -Capture $data -StartUtc $start -EndUtc $start.AddSeconds(3)}catch{$rejected=$true}
    if(-not $rejected){throw "Invalid CPU evidence accepted: $case."}
    $checks++
}
Write-Output "Passed $checks utilization integration cases."
