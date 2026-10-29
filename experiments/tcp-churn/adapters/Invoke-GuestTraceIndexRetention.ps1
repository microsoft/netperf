# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][pscredential]$Credential,
    [Parameter(Mandatory)][long[]]$CollectionStartTicks,
    [Parameter(Mandatory)][string]$ReportFile,
    [switch]$Prune,
    [switch]$AllowInactiveRecorderMetadata,
    [string]$VmName='netperf-windows-2022-client'
)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $ReportFile){throw 'Use a fresh numeric retention report.'}
$worker={
    param([long[]]$AllowedTicks,[bool]$RemoveIndexes,[bool]$PermitInactiveMetadata)
    $ErrorActionPreference='Stop'
    function Get-TraceContentHash([string]$Path) {
        $hash=[Security.Cryptography.SHA256]::Create()
        try {
            $stream=[IO.File]::OpenRead($Path)
            try{[BitConverter]::ToString($hash.ComputeHash($stream)).Replace('-','')}
            finally{$stream.Dispose()}
        }finally{$hash.Dispose()}
    }
    function Read-RecorderStatus([string]$Executable,[string]$Arguments) {
        $settings=[Diagnostics.ProcessStartInfo]::new()
        $settings.FileName=$Executable;$settings.Arguments=$Arguments
        $settings.UseShellExecute=$false;$settings.RedirectStandardOutput=$true;$settings.RedirectStandardError=$true
        $query=[Diagnostics.Process]::new();$query.StartInfo=$settings
        try {
            if(-not $query.Start()){throw 'The read-only recorder status query did not start.'}
            $output=$query.StandardOutput.ReadToEndAsync();$errorOutput=$query.StandardError.ReadToEndAsync()
            if(-not $query.WaitForExit(15000)){
                Stop-Process -Id $query.Id -Force -ErrorAction Stop
                throw 'The read-only recorder status query exceeded its deadline.'
            }
            [pscustomobject]@{ExitCode=$query.ExitCode;Text=($output.GetAwaiter().GetResult()+$errorOutput.GetAwaiter().GetResult())}
        }finally{$query.Dispose()}
    }
    function Get-OwnedIndexPlan([string]$Parent,[long[]]$Ticks,[Collections.IDictionary]$Details) {
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
            if($null -ne $Details){
                $Details.examinedCollections++
                if(@($Ticks|Where-Object{[Math]::Abs($tick-$_) -le [TimeSpan]::FromMinutes(5).Ticks}).Count -and
                    -not $Details.nearbyTicks.Contains($tick)){$Details.nearbyTicks.Add($tick)}
            }
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
                    MarkerHash=(Get-TraceContentHash $marker)
                    Index=$index;Raw=$raw;IndexBytes=$indexFile.Length
                    IndexWriteTicks=$indexFile.LastWriteTimeUtc.Ticks;RawHash=(Get-TraceContentHash $raw)})
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
                (Get-TraceContentHash $entry.Marker) -ne $entry.MarkerHash -or
                $current.Extension -ne '.etlx' -or ($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
                $current.Length -ne $entry.IndexBytes -or $current.LastWriteTimeUtc.Ticks -ne $entry.IndexWriteTicks -or
                (Get-TraceContentHash $entry.Raw) -ne $entry.RawHash){
                throw 'An owned derived index or its original ETL changed after planning.'
            }
        }
        foreach($entry in $Plan){
            Remove-Item -LiteralPath $entry.Index -ErrorAction Stop
            if((Get-TraceContentHash $entry.Raw) -ne $entry.RawHash){
                throw 'Original ETL integrity did not verify after derived-index removal.'
            }
        }
    }
    $active=@([Diagnostics.Process]::GetProcesses()|Where-Object{$_.ProcessName -in @('ArrivalTcp','CpuSamples','ctsTraffic','Runner.Worker')})
    if($active.Count){throw 'The guest has an active workload or analyzer.'}
    $query=Read-RecorderStatus -Executable "$env:SystemRoot\System32\wpr.exe" -Arguments '-status'
    $status=$query.Text;$statusCode=$query.ExitCode
    $inactiveMetadata=$false
    if($statusCode -ne 0 -or $status -notmatch '(?i)wpr is not recording|recording is not running'){
        if(-not $PermitInactiveMetadata -or $statusCode -eq 0){throw 'An idle WPR state is required for derived-index retention.'}
        $loggerRows=@(& logman.exe query -ets)
        if($LASTEXITCODE -ne 0){throw 'The independent active-session query failed.'}
        if(@($loggerRows|Where-Object{$_ -match '^\s*(WPR_initiated_|TcpChurnExact-)'}).Count){
            throw 'Active recording sessions forbid derived-index retention.'
        }
        $inactiveMetadata=$true
    }
    $drive=[IO.Path]::GetPathRoot($env:TEMP).Substring(0,1)
    $before=[long](Get-PSDrive -Name $drive).Free
    $details=@{examinedCollections=0;nearbyTicks=[Collections.Generic.List[long]]::new()}
    try{$plan=@(Get-OwnedIndexPlan $env:TEMP $AllowedTicks $details)}catch{
        if($_.Exception.Message -notmatch 'Not every allowed synthetic collection'){throw}
        return [pscustomobject]@{schema=1;outcome='failed';failureReason='collection-match'
            requestedCollectionTicks=$AllowedTicks;nearbyCollectionTicks=$details.nearbyTicks.ToArray()
            examinedCollections=$details.examinedCollections;temporaryFreeMiBBefore=[long][Math]::Floor($before/1MB)
            pruned=$false;pathsExported=$false;rawTracesExported=$false}
    }
    $bytes=[long]0
    foreach($entry in $plan){$bytes+=$entry.IndexBytes}
    if($RemoveIndexes){Remove-OwnedIndexes $plan}
    [pscustomobject]@{schema=1;outcome=$(if($RemoveIndexes){'pruned-derived-indexes'}else{'inspected'})
        matchedCollections=$AllowedTicks.Count;derivedIndexCount=$plan.Count;derivedIndexBytes=$bytes
        pruned=$RemoveIndexes;originalEtlHashesPreserved=$true
        temporaryFreeMiBBefore=[long][Math]::Floor($before/1MB)
        temporaryFreeMiBAfter=[long][Math]::Floor((Get-PSDrive -Name $drive).Free/1MB)
        inactiveRecorderMetadataObserved=$inactiveMetadata;recorderStatusExitCode=$statusCode
        pathsExported=$false;rawTracesExported=$false}
}
try{
    $report=Invoke-Command -VMName $VmName -Credential $Credential -ErrorAction Stop -ScriptBlock $worker `
        -ArgumentList $CollectionStartTicks,([bool]$Prune),([bool]$AllowInactiveRecorderMetadata)
    $report|Select-Object schema,outcome,matchedCollections,derivedIndexCount,derivedIndexBytes,pruned,
        originalEtlHashesPreserved,temporaryFreeMiBBefore,temporaryFreeMiBAfter,pathsExported,rawTracesExported,
        inactiveRecorderMetadataObserved,recorderStatusExitCode,
        failureReason,requestedCollectionTicks,nearbyCollectionTicks,examinedCollections|
        ConvertTo-Json|Set-Content -LiteralPath $ReportFile
    if($report.outcome -eq 'failed'){throw 'The exact retention collection match failed; no files were removed.'}
}catch{
    $reason=switch -Regex ($_.Exception.Message){
        'active workload or analyzer' {'busy';break}
        'idle WPR state' {'recording-active';break}
        'Active recording sessions' {'recording-active';break}
        'Not every allowed synthetic collection' {'collection-match';break}
        'matched more than one owned root' {'duplicate-collection';break}
        'changed after planning' {'scope-changed';break}
        'reparse point' {'reparse-point';break}
        'nonempty original ETL' {'original-trace';break}
        'not enough space|disk is full|disk full' {'storage';break}
        default {'unclassified'}
    }
    if(-not(Test-Path -LiteralPath $ReportFile)){
        $id=[string]$_.FullyQualifiedErrorId
        $line=[regex]::Match([string]$_.ScriptStackTrace,'(?i)line\s+(\d+)')
        $message=$_.Exception.Message
        @{schema=1;outcome='failed';failureType=$_.Exception.GetType().FullName;failureCode=$_.Exception.HResult
            errorId=$(if($id -match '^[A-Za-z0-9_.,-]{1,256}$'){$id}else{'unclassified'})
            sourceLine=$(if($line.Success){[int]$line.Groups[1].Value}else{$_.InvocationInfo.ScriptLineNumber})
            publicDiagnosticTerms=@('native','command','query','session','file','hash','path','not','found','access','denied',
                'space','disk','json','invalid','convert','null','variable','property','method','argument','buffer','count','cannot','enough','process','used','another'|
                Where-Object{$message -match ('(?i)\b'+[regex]::Escape($_)+'\b')})
            failureReason=$reason;pathsExported=$false;rawTracesExported=$false}|ConvertTo-Json|Set-Content -LiteralPath $ReportFile
    }
    throw 'The bounded guest trace-index retention operation failed; no private paths or raw traces were published.'
}
