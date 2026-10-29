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
$cleanup=@($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.ScriptBlockExpressionAst] -and
        $node.Extent.Text.Contains('$errors=[Collections.Generic.List[Exception]]::new()') -and
        $node.Extent.Text.Contains('$global:OwnedManagedGcPeer.PressureServer')
},$true))
if($cleanup.Count -ne 1){throw 'The actual owned peer cleanup must be uniquely identified.'}
try{
    $global:OwnedManagedGcPeer=@{Process='data';PressureClient='pressure-client';PressureServer='pressure-server';Rule='owned-test-rule'}
    $stopped=[Collections.Generic.List[string]]::new();$ruleRemoved=$false
    function Stop-TcpChurnCollector {
        param($Child)
        $stopped.Add($Child)
        if($Child -eq 'data'){throw 'Synthetic first-child stop failure.'}
    }
    function Remove-NetFirewallRule {
        [CmdletBinding()]param($Name)
        if($Name -ne 'owned-test-rule'){throw 'An unowned rule was removed.'}
        $script:ruleRemoved=$true
    }
    $rejected=$false
    try{& $cleanup[0].ScriptBlock.GetScriptBlock()}catch{
        if($_.Exception.Message -notmatch 'Owned peer workload cleanup failed'){throw}
        $rejected=$true
    }
    if(-not $rejected -or $stopped.Count -ne 3 -or -not $ruleRemoved){
        throw 'A peer stop error prevented another owned child or rule from being cleaned.'
    }
}finally{Remove-Variable -Name OwnedManagedGcPeer -Scope Global}
Write-Output 'Passed standalone/combined path plans and failure-safe companion cleanup; no network operations were performed.'
