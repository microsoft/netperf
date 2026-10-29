# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'adapters\Invoke-ManagedGcPeerDiagnostic.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
$plan=@($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.IfStatementAst] -and
        $node.Clauses[0].Item1.Extent.Text -eq '$RouteRefresh -or $CacheRetirePaths'
},$true))
if($plan.Count -ne 1){throw 'The actual path-control launch plan must be uniquely identified.'}
foreach($case in @('route','cache','both')){
    & {
        $RouteRefresh=$case -ne 'cache';$CacheRetirePaths=if($case -ne 'route'){24576}else{0}
        $cacheStem=if($RouteRefresh -and $CacheRetirePaths){'cache-control'}else{'route-control'}
        $RouteVariant='peer-gateway';$alias='synthetic-owned-interface';$peerMac='02-00-00-00-00-02'
        $diagnostics=Join-Path ([IO.Path]::GetTempPath()) 'unused-control-plan'
        $localOutput=Join-Path $diagnostics 'server.json';$exe=Join-Path $diagnostics 'ArrivalTcp.exe'
        $localServer=[pscustomobject]@{Process=[pscustomobject]@{Id=42}}
        $pathControls=[Collections.Generic.List[object]]::new()
        $launches=[Collections.Generic.List[object]]::new()
        function Start-TcpChurnCollector {
            param($Program,$Arguments,$Directory,$LogPrefix)
            $launches.Add([pscustomobject]@{Arguments=$Arguments;LogPrefix=$LogPrefix})
            [pscustomobject]@{Process=$null}
        }
        function Wait-Ready {param($Child,$File,$TimeoutSeconds)}
        $adapterRoot=Split-Path $ast.Extent.File
        & ([scriptblock]::Create('$PSScriptRoot=$adapterRoot;'+$plan[0].Extent.Text))
        $expected=if($case -eq 'both'){2}else{1}
        if($pathControls.Count -ne $expected -or $launches.Count -ne $expected){
            throw 'A selected path control was dropped or duplicated.'
        }
        if($case -eq 'both' -and (@($pathControls.Stem|Sort-Object)-join ',') -ne 'cache-control,route-control'){
            throw 'Combined controls must not share snapshots, stop files or report stems.'
        }
        if($case -ne 'both' -and $pathControls[0].Stem -ne 'route-control'){
            throw 'A standalone control changed its established lifecycle layout.'
        }
        foreach($control in $pathControls){
            if($null -eq $control.Child -or
                @($control.Arguments|Where-Object{$_ -eq (Join-Path $diagnostics ($control.Stem+'-original.clixml'))}).Count -ne 1){
                throw 'Each launched control must retain its own restoration arguments.'
            }
        }
    }
}
Write-Output 'Passed route-only, cache-only and combined production control-plan checks; no network operations were performed.'
