# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][pscredential]$Credential,
    [Parameter(Mandatory)][long[]]$CollectionStartTicks,
    [Parameter(Mandatory)][string]$ReportFile,
    [switch]$Prune,
    [string]$VmName='netperf-windows-2022-client'
)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $ReportFile){throw 'Use a fresh numeric retention report.'}
$worker={
    param([long[]]$AllowedTicks,[bool]$RemoveIndexes)
    $ErrorActionPreference='Stop'
    function Get-OwnedIndexPlan([string]$Parent,[long[]]$Ticks) {
        if(-not $Ticks.Count -or @($Ticks|Sort-Object -Unique).Count -ne $Ticks.Count -or @($Ticks|Where-Object{$_ -le 0}).Count){
            throw 'Distinct positive synthetic collection timestamps are required.'
        }
        $matchedCollections=@{};$plan=[Collections.Generic.List[object]]::new()
        foreach($root in Get-ChildItem -LiteralPath $Parent -Directory -Filter 'netperf-churn-*'){
            if($root.Name -notmatch '^netperf-churn-[0-9a-f]{32}$'){continue}
            if($root.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'An owned-root candidate is a reparse point.'}
            $diagnostics=Join-Path $root.FullName 'managed-gc-diagnostics'
            if(-not(Test-Path -LiteralPath $diagnostics -PathType Container)){continue}
            if((Get-Item -LiteralPath $diagnostics).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'A diagnostic directory is a reparse point.'}
            $marker=Join-Path $diagnostics 'profiled-server.json.gc.json'
            if(-not(Test-Path -LiteralPath $marker -PathType Leaf)){continue}
            if((Get-Item -LiteralPath $marker).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'A collection marker is a reparse point.'}
            $gc=Get-Content -LiteralPath $marker -Raw|ConvertFrom-Json
            if(-not $gc.enabled -or $gc.heapLayout -ne 'graph' -or $gc.heapMiB -ne 1024){continue}
            $tick=([datetime]$gc.collectionStartUtc).ToUniversalTime().Ticks
            if($tick -notin $Ticks){continue}
            if($matchedCollections.ContainsKey($tick)){throw 'An allowed collection timestamp matched more than one owned root.'}
            $matchedCollections[$tick]=$true
            foreach($stem in @('cpu','tcp','clr')){
                $index=Join-Path $diagnostics ($stem+'.etlx')
                if(-not(Test-Path -LiteralPath $index -PathType Leaf)){continue}
                $raw=Join-Path $diagnostics ($stem+'.etl')
                $indexFile=Get-Item -LiteralPath $index
                $rawFile=Get-Item -LiteralPath $raw -ErrorAction Stop
                if(($indexFile.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
                    ($rawFile.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $rawFile.Length -le 0){
                    throw 'A derived index requires an ordinary, nonempty original ETL.'
                }
                $plan.Add([pscustomobject]@{Root=$root.FullName;Diagnostics=$diagnostics;Marker=$marker
                    MarkerHash=(Get-FileHash -LiteralPath $marker -Algorithm SHA256).Hash
                    Index=$index;Raw=$raw;IndexBytes=$indexFile.Length
                    IndexWriteTicks=$indexFile.LastWriteTimeUtc.Ticks;RawHash=(Get-FileHash -LiteralPath $raw -Algorithm SHA256).Hash})
            }
        }
        if($matchedCollections.Count -ne $Ticks.Count){throw 'Not every allowed synthetic collection matched exactly one owned root.'}
        $plan.ToArray()
    }
    function Remove-OwnedIndexes([object[]]$Plan) {
        foreach($entry in $Plan){
            $current=Get-Item -LiteralPath $entry.Index -ErrorAction Stop
            if(((Get-Item -LiteralPath $entry.Root).Attributes -band [IO.FileAttributes]::ReparsePoint) -or
                ((Get-Item -LiteralPath $entry.Diagnostics).Attributes -band [IO.FileAttributes]::ReparsePoint) -or
                (Get-FileHash -LiteralPath $entry.Marker -Algorithm SHA256).Hash -ne $entry.MarkerHash -or
                $current.Extension -ne '.etlx' -or ($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
                $current.Length -ne $entry.IndexBytes -or $current.LastWriteTimeUtc.Ticks -ne $entry.IndexWriteTicks -or
                (Get-FileHash -LiteralPath $entry.Raw -Algorithm SHA256).Hash -ne $entry.RawHash){
                throw 'An owned derived index or its original ETL changed after planning.'
            }
        }
        foreach($entry in $Plan){
            Remove-Item -LiteralPath $entry.Index -ErrorAction Stop
            if((Get-FileHash -LiteralPath $entry.Raw -Algorithm SHA256).Hash -ne $entry.RawHash){
                throw 'Original ETL integrity did not verify after derived-index removal.'
            }
        }
    }
    $active=@([Diagnostics.Process]::GetProcesses()|Where-Object{$_.ProcessName -in @('ArrivalTcp','CpuSamples','ctsTraffic','Runner.Worker')})
    if($active.Count){throw 'The guest has an active workload or analyzer.'}
    $status=(& wpr.exe -status 2>&1|Out-String);$statusCode=$LASTEXITCODE
    if($statusCode -ne 0 -or $status -notmatch '(?i)wpr is not recording|recording is not running'){
        throw 'An idle WPR state is required for derived-index retention.'
    }
    $drive=[IO.Path]::GetPathRoot($env:TEMP).Substring(0,1)
    $before=[long](Get-PSDrive -Name $drive).Free
    $plan=@(Get-OwnedIndexPlan $env:TEMP $AllowedTicks)
    $bytes=[long]0
    foreach($entry in $plan){$bytes+=$entry.IndexBytes}
    if($RemoveIndexes){Remove-OwnedIndexes $plan}
    [pscustomobject]@{schema=1;outcome=$(if($RemoveIndexes){'pruned-derived-indexes'}else{'inspected'})
        matchedCollections=$AllowedTicks.Count;derivedIndexCount=$plan.Count;derivedIndexBytes=$bytes
        pruned=$RemoveIndexes;originalEtlHashesPreserved=$true
        temporaryFreeMiBBefore=[long][Math]::Floor($before/1MB)
        temporaryFreeMiBAfter=[long][Math]::Floor((Get-PSDrive -Name $drive).Free/1MB)
        pathsExported=$false;rawTracesExported=$false}
}
try{
    $report=Invoke-Command -VMName $VmName -Credential $Credential -ErrorAction Stop -ScriptBlock $worker `
        -ArgumentList $CollectionStartTicks,([bool]$Prune)
    $report|Select-Object schema,outcome,matchedCollections,derivedIndexCount,derivedIndexBytes,pruned,
        originalEtlHashesPreserved,temporaryFreeMiBBefore,temporaryFreeMiBAfter,pathsExported,rawTracesExported|
        ConvertTo-Json|Set-Content -LiteralPath $ReportFile
}catch{
    @{schema=1;outcome='failed';failureType=$_.Exception.GetType().FullName;failureCode=$_.Exception.HResult
        pathsExported=$false;rawTracesExported=$false}|ConvertTo-Json|Set-Content -LiteralPath $ReportFile
    throw 'The bounded guest trace-index retention operation failed; no private paths or raw traces were published.'
}
