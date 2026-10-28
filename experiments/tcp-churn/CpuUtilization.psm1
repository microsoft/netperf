# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Measure-LogicalProcessorUtilization {
    param([Parameter(Mandatory)]$Capture,[Parameter(Mandatory)][datetime]$StartUtc,[Parameter(Mandatory)][datetime]$EndUtc)
    $StartUtc=$StartUtc.ToUniversalTime();$EndUtc=$EndUtc.ToUniversalTime()
    if($Capture.outcome -ne 'collected' -or $EndUtc -le $StartUtc){throw 'A completed capture and positive measurement interval are required.'}
    if($null -eq $Capture.PSObject.Properties['snapshot'] -or $Capture.snapshot -ne 'coherent-pdh-query') {
        throw 'A coherent, timestamped PDH snapshot is required; sequential counter vectors are not accepted.'
    }
    if($null -eq $Capture.PSObject.Properties['timestampSource'] -or
        $Capture.timestampSource -ne 'Utc-bracketed-PdhCollectQueryDataWithTime' -or
        $null -eq $Capture.PSObject.Properties['maximumQueryMilliseconds'] -or
        $null -eq $Capture.maximumQueryMilliseconds -or
        $Capture.maximumQueryMilliseconds -is [bool] -or $Capture.maximumQueryMilliseconds -is [string] -or
        -not [double]::IsFinite([double]$Capture.maximumQueryMilliseconds) -or
        $Capture.maximumQueryMilliseconds -lt 0 -or $Capture.maximumQueryMilliseconds -gt 100) {
        throw 'CPU snapshots require bounded UTC alignment; opaque provider timestamps are not accepted as UTC.'
    }
    $names=@($Capture.instances)
    if(-not $names.Count -or @($names|Sort-Object -Unique).Count -ne $names.Count -or
        @($names|Where-Object{$_ -notmatch '^\d+,\d+$'}).Count){throw 'Use distinct group-relative processor instances.'}
    $weighted=[double[]]::new($names.Count);$peaks=[double[]]::new($names.Count)
    $coverage=0.0;$busy=0.0;$saturated=0.0;$peakBusy=0.0;$peakSaturated=0;$clipped=0;$last=$null
    foreach($row in $Capture.intervals) {
        $start=if($row.startUtc -is [DateTime]){$row.startUtc.ToUniversalTime()}else{
            [DateTime]::Parse($row.startUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
        }
        $end=if($row.endUtc -is [DateTime]){$row.endUtc.ToUniversalTime()}else{
            [DateTime]::Parse($row.endUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
        }
        if($end -le $start -or ($null -ne $last -and $start -lt $last)){throw 'CPU counter intervals overlap or have invalid ordering.'}
        $last=$end
        $duration=([DateTime]([Math]::Min($end.Ticks,$EndUtc.ToUniversalTime().Ticks))-
            [DateTime]([Math]::Max($start.Ticks,$StartUtc.ToUniversalTime().Ticks))).TotalSeconds
        if($duration -le 0){continue}
        if(@($row.percentBusy).Count -ne $names.Count){throw 'CPU vector length differs from the instance list.'}
        $sum=0.0;$count=0
        foreach($index in 0..($names.Count-1)) {
            if($null -eq $row.percentBusy[$index] -or $row.percentBusy[$index] -is [bool] -or
                $row.percentBusy[$index] -is [string]){throw 'CPU utilization must be numeric, not null, Boolean or text.'}
            $value=[double]$row.percentBusy[$index]
            if(-not [double]::IsFinite($value) -or $value -lt -1 -or $value -gt 101){throw 'Invalid CPU utilization sample.'}
            if($value -lt 0 -or $value -gt 100){$clipped++;$value=[Math]::Clamp($value,0,100)}
            $weighted[$index]+=$value*$duration;$peaks[$index]=[Math]::Max($peaks[$index],$value)
            $sum+=$value/100.0
            if($value -ge 90){$count++}
        }
        $coverage+=$duration;$busy+=$sum*$duration;$saturated+=$count*$duration
        $peakBusy=[Math]::Max($peakBusy,$sum);$peakSaturated=[Math]::Max($peakSaturated,$count)
    }
    if($coverage -lt 0.9*($EndUtc.ToUniversalTime()-$StartUtc.ToUniversalTime()).TotalSeconds){throw 'CPU counters cover less than 90 percent of the measurement interval.'}
    [pscustomobject][ordered]@{
        schema=1;snapshot='coherent-pdh-query';logicalProcessors=$names.Count;coveredSeconds=$coverage;busyCpuSeconds=$busy
        averageBusyCpuEquivalents=$busy/$coverage;peakBusyCpuEquivalents=$peakBusy
        averageProcessorsAtLeast90Percent=$saturated/$coverage;peakProcessorsAtLeast90Percent=$peakSaturated
        clippedRoundingSamples=$clipped
        processors=@(foreach($index in 0..($names.Count-1)){
            [pscustomobject]@{processor=$names[$index];averagePercentBusy=$weighted[$index]/$coverage;peakPercentBusy=$peaks[$index]}
        })
        targetLockAttribution='not-derived-from-utilization-counters'
    }
}
Export-ModuleMember -Function Measure-LogicalProcessorUtilization
