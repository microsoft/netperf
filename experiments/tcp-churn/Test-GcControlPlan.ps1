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
foreach($case in @('route','cache','both','unused-cache','flush','after-gc-route')){
    & {
        $RouteRefresh=$case -ne 'cache';$CacheRetirePaths=if($case -ne 'route'){24576}else{0}
        if($case -eq 'unused-cache'){$RouteRefresh=$false;$CacheRetirePaths=49152}
        if($case -eq 'cache'){$CacheRetirePaths=1}
        if($case -in @('flush','after-gc-route')){$CacheRetirePaths=0}
        $CacheInterfaceGuid=if($case -eq 'unused-cache'){'owned-guid'}else{''}
        $CacheInterfaceAlias=if($case -eq 'unused-cache'){'NetperfPath-123456abcdef'}else{''}
        $cacheStem=if($RouteRefresh -and $CacheRetirePaths){'cache-control'}else{'route-control'}
        $RouteVariant=if($case -eq 'flush'){'destination-flush'}elseif($case -eq 'after-gc-route'){'onlink-after-gc'}else{'peer-gateway'}
        $alias='synthetic-owned-interface';$peerMac='02-00-00-00-00-02'
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
        if($case -eq 'after-gc-route'){
            $beginIndex=[Array]::IndexOf($launches[0].Arguments,'-BeginFile')
            if($beginIndex -lt 0 -or $launches[0].Arguments[$beginIndex+1] -ne ($localOutput+'.gc.json') -or
                (Split-Path $pathControls[0].Arguments[3] -Leaf) -ne 'Invoke-ScopedPathRefresh.ps1'){
                throw 'The timing-only route contrast must use the existing route worker and actual GC-completion file.'
            }
        }
        foreach($control in $pathControls){
            if($null -eq $control.Child -or
                @($control.Arguments|Where-Object{$_ -eq (Join-Path $diagnostics ($control.Stem+'-original.clixml'))}).Count -ne 1){
                throw 'Each launched control must retain its own restoration arguments.'
            }
            $endIndex=[Array]::IndexOf($control.Arguments,'-EndFile')
            if($case -in @('unused-cache','flush')){
                if($endIndex -lt 0 -or $control.Arguments[$endIndex+1] -ne ($localOutput+'.gc.json')){
                    throw 'Unused-interface retirement must use the actual receiver GC-completion observation.'
                }
            }elseif($endIndex -ge 0){throw 'A non-unused-interface control changed its GC-start trigger.'}
            if($case -eq 'flush' -and
                ((Split-Path $control.Arguments[3] -Leaf) -ne 'Invoke-ScopedDestinationCacheFlush.ps1' -or
                    '-NextHop' -in $control.Arguments -or '-ReceiverProcessId' -notin $control.Arguments)){
                throw 'The atomic destination-flush plan used a route mutation or lost receiver ownership.'
            }
            $countIndex=[Array]::IndexOf($control.Arguments,'-PathCount')
            if($countIndex -ge 0 -and $control.Arguments[$countIndex+1] -ne [string]$CacheRetirePaths){
                throw 'The requested cache fixture count was changed during actual child argument transport.'
            }
        }
    }
}
$traffic=[Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'adapters\GcReceiverTraffic.psm1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
$peerLaunch=@($traffic.FindAll({
    param($node)
    $node -is [Management.Automation.Language.ScriptBlockExpressionAst] -and
        $node.Extent.Text.Contains('pressure-client.json') -and
        'root' -in @($node.ScriptBlock.ParamBlock.Parameters.Name.VariablePath.UserPath)
},$true))
if($peerLaunch.Count -ne 1){throw 'The actual independent peer launch must be uniquely identified.'}
foreach($pressureEnabled in @($false,$true)){
    try{
        $global:OwnedManagedGcPeer=@{}
        $peerChildren=[Collections.Generic.List[object]]::new()
        function Start-TcpChurnCollector {
            param($Program,$Arguments,$Directory,$LogPrefix)
            $peerChildren.Add([pscustomobject]@{Arguments=$Arguments})
            [pscustomobject]@{Process=$null}
        }
        & $peerLaunch[0].ScriptBlock.GetScriptBlock() 'unused-owned-root' '192.0.2.1' '192.0.2.2' 20300 4096 4096 1460 1024 $pressureEnabled 64
        if($peerChildren.Count -ne $(if($pressureEnabled){2}else{1})){throw 'Optional pressure changed the ordinary peer launch count.'}
        if($peerChildren[0].Arguments.Count -ne 14 -or $peerChildren[0].Arguments[13] -ne 'exchanges:64'){
            throw 'The actual persistent producer lost its exchange-count protocol argument.'
        }
        if($pressureEnabled -and
            ($peerChildren[1].Arguments[3] -ne '4096' -or $peerChildren[1].Arguments[4] -ne '2048' -or
                $peerChildren[1].Arguments[5] -ne '1048576' -or $peerChildren[1].Arguments[10] -ne '256' -or
                $global:OwnedManagedGcPeer.PressureRate -ne 2048)){
            throw 'The actual independent pressure workload lost its bounded count, rate, payload or concurrency.'
        }
    }finally{Remove-Variable -Name OwnedManagedGcPeer -Scope Global}
}
$selection=@($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.IfStatementAst] -and
        $node.Clauses[0].Item1.Extent.Text -eq '$ExchangesPerConnection -eq 64' -and
        $node.Extent.Text.Contains('$omittedTcpTasks=')
},$true))
if($selection.Count -ne 1){throw 'The actual persistent TCP event selection must be identified.'}
foreach($exchangeMode in @(1,64)){
    & {
        $ExchangesPerConnection=$exchangeMode
        $tasks=@('TcpTcbSynSend','TcpDisconnectTcbRtoTimeout','TcpDataTransferRetransmitRound',
            'TcpBlackHoleDetectionEntry','TcpBlackHoleDetectionExit','TcpBlackHoleDetectionFailed','TcpBhDetectFullSizeAck',
            'TcpZeroWindowProbingBegin','TcpZeroWindowProbingEnd','TcpAcceptListenerComplete','TcpCloseTcbRequest','TcpInsertConnectionTuple')
        $tcpKeywords=[long]0x500000084;$omittedTcpTasks=@()
        . ([scriptblock]::Create($selection[0].Extent.Text))
        foreach($required in @('TcpTcbSynSend','TcpDisconnectTcbRtoTimeout','TcpAcceptListenerComplete',
            'TcpCloseTcbRequest','TcpInsertConnectionTuple','TcpBlackHoleDetectionEntry','TcpBlackHoleDetectionExit','TcpBlackHoleDetectionFailed')){
            if($required -notin $tasks){throw 'Persistent selection lost required lifetime or actual BH event coverage.'}
        }
        if($exchangeMode -eq 64 -and
            (($tcpKeywords -band [long]0x100000080) -ne 0 -or $omittedTcpTasks.Count -ne 4 -or
                @($tasks|Where-Object{$_ -in $omittedTcpTasks}).Count)){
            throw 'Persistent selection retained broad per-message send/diagnosis event volume.'
        }
        if($exchangeMode -eq 1 -and ($tcpKeywords -ne [long]0x500000084 -or $omittedTcpTasks.Count)){
            throw 'The ordinary single-exchange capture changed its default event coverage.'
        }
        $metadata=@((Get-WinEvent -ListProvider Microsoft-Windows-TCPIP).Events|Where-Object{$null -ne $_.Task -and $_.Task.Name -in $tasks})
        foreach($required in $tasks){if($required -notin @($metadata.Task.Name)){throw 'A selected task is absent from the installed public manifest.'}}
        foreach($event in $metadata){
            if(@($event.Keywords).Count -and -not @($event.Keywords|Where-Object{($_.Value -band $tcpKeywords) -ne 0}).Count){
                throw 'Narrowed persistent keywords do not cover a selected public event.'
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
