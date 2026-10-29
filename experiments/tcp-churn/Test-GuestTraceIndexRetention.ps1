# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'adapters\Invoke-GuestTraceIndexRetention.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
$functions=@($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -in @('Get-OwnedIndexPlan','Remove-OwnedIndexes')
},$true))
if($functions.Count -ne 2){throw 'The actual retention planning/removal functions must be identified.'}
. ([scriptblock]::Create(($functions|ForEach-Object{$_.Extent.Text})-join "`n"))
$directory=Join-Path ([IO.Path]::GetTempPath()) ('trace-index-test-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $directory
try{
    foreach($case in @('inspect','prune','wrong-collection','changed-index','changed-raw','changed-marker')){
        $root=Join-Path $directory ('netperf-churn-'+[guid]::NewGuid().ToString('N'))
        $diagnostics=Join-Path $root 'managed-gc-diagnostics'
        $null=New-Item -ItemType Directory -Path $diagnostics
        $marker=Join-Path $diagnostics 'profiled-server.json.gc.json'
        $time=[datetime]::UtcNow
        @{enabled=$true;heapMiB=1024;heapLayout='graph';collectionStartUtc=$time.ToString('o')}|
            ConvertTo-Json|Set-Content -LiteralPath $marker
        $raw=Join-Path $diagnostics 'cpu.etl';$index=Join-Path $diagnostics 'cpu.etlx'
        [IO.File]::WriteAllText($raw,'original synthetic trace fixture')
        [IO.File]::WriteAllText($index,'regenerable synthetic index fixture')
        $rejected=$false
        try{
            $tick=if($case -eq 'wrong-collection'){$time.Ticks+1}else{$time.Ticks}
            $plan=@(Get-OwnedIndexPlan $directory @($tick))
            if($plan.Count -ne 1 -or $plan[0].Index -ne $index){throw 'The actual plan did not isolate the selected derived index.'}
            if($case -eq 'changed-index'){[IO.File]::AppendAllText($index,'changed')}
            if($case -eq 'changed-raw'){[IO.File]::AppendAllText($raw,'changed')}
            if($case -eq 'changed-marker'){[IO.File]::AppendAllText($marker,' ')}
            if($case -ne 'inspect'){Remove-OwnedIndexes $plan}
        }catch{
            if($case -notin @('wrong-collection','changed-index','changed-raw','changed-marker') -or
                $_.Exception.Message -notmatch 'Not every allowed synthetic collection|changed after planning'){throw}
            $rejected=$true
        }
        if($rejected -ne ($case -in @('wrong-collection','changed-index','changed-raw','changed-marker')) -or
            -not(Test-Path -LiteralPath $raw) -or
            (Test-Path -LiteralPath $index) -ne ($case -ne 'prune')){
            throw 'Retention deleted an original trace, mutated a rejected scope, or failed to remove only a derived index.'
        }
        foreach($path in @($marker,$raw,$index)){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path}}
        Remove-Item -LiteralPath $diagnostics;Remove-Item -LiteralPath $root
    }
    foreach($prune in @($false,$true)){
        & {
            $expectedPruneMode=$prune
            $reportFile=Join-Path $directory $(if($prune){'host-prune.json'}else{'host-inspect.json'})
            function Invoke-Command {
                [CmdletBinding()]param($VMName,$Credential,$ScriptBlock,$ArgumentList)
                if($VMName -ne 'netperf-windows-2022-client' -or $ArgumentList.Count -ne 2 -or
                    @($ArgumentList[0]).Count -ne 2 -or $ArgumentList[0][0] -ne 1001 -or
                    $ArgumentList[0][1] -ne 1002 -or $ArgumentList[1] -isnot [bool] -or $ArgumentList[1] -ne $expectedPruneMode){
                    throw 'The actual host call flattened collection ticks or lost the explicit prune mode.'
                }
                [pscustomobject]@{schema=1;outcome='tested';matchedCollections=2;derivedIndexCount=2
                    derivedIndexBytes=40;pruned=$expectedPruneMode;originalEtlHashesPreserved=$true
                    temporaryFreeMiBBefore=10;temporaryFreeMiBAfter=10;pathsExported=$false;rawTracesExported=$false
                    PSComputerName='unpublishable-test-host';privatePath='unpublishable-test-path'}
            }
            $credential=[pscredential]::new('unused-test-only',(ConvertTo-SecureString 'unused-test-only' -AsPlainText -Force))
            & (Join-Path $PSScriptRoot 'adapters\Invoke-GuestTraceIndexRetention.ps1') `
                -Credential $credential -CollectionStartTicks @(1001,1002) -ReportFile $reportFile -Prune:$prune
            $text=Get-Content -LiteralPath $reportFile -Raw
            $report=$text|ConvertFrom-Json
            if($text -match 'unpublishable' -or $report.pruned -ne $prune -or $report.matchedCollections -ne 2){
                throw 'The actual host retention serializer leaked identity or changed the numeric report.'
            }
            Remove-Item -LiteralPath $reportFile
        }
    }
    & {
        function Invoke-Command {
            [CmdletBinding()]param($VMName,$Credential,$ScriptBlock,$ArgumentList)
            throw 'Not every allowed synthetic collection matched exactly one owned root.'
        }
        $credential=[pscredential]::new('unused-test-only',(ConvertTo-SecureString 'unused-test-only' -AsPlainText -Force))
        $reportFile=Join-Path $directory 'host-failed.json'
        $rejected=$false
        try{& (Join-Path $PSScriptRoot 'adapters\Invoke-GuestTraceIndexRetention.ps1') `
            -Credential $credential -CollectionStartTicks @(1001) -ReportFile $reportFile}catch{
            if($_.Exception.Message -notmatch 'bounded guest trace-index retention operation failed'){throw}
            $rejected=$true
        }
        $failure=Get-Content -LiteralPath $reportFile -Raw|ConvertFrom-Json
        if(-not $rejected -or $failure.outcome -ne 'failed' -or $failure.failureReason -ne 'collection-match'){
            throw 'A rejected collection must retain its fixed public-safe failure reason.'
        }
        Remove-Item -LiteralPath $reportFile
    }
    'Passed actual owned-index retention, changed-scope/raw/index rejection, array/bool transport and safe success/failure serialization; originals preserved.'
}finally{
    foreach($name in @('host-inspect.json','host-prune.json','host-failed.json')){
        $path=Join-Path $directory $name
        if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path}
    }
    foreach($root in Get-ChildItem -LiteralPath $directory -Directory){
        $diagnostics=Join-Path $root.FullName 'managed-gc-diagnostics'
        foreach($name in @('profiled-server.json.gc.json','cpu.etl','cpu.etlx')){
            $path=Join-Path $diagnostics $name
            if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path}
        }
        Remove-Item -LiteralPath $diagnostics;Remove-Item -LiteralPath $root.FullName
    }
    Remove-Item -LiteralPath $directory
}
