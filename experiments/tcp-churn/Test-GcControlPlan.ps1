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
foreach($case in @('route','cache','both','unused-cache','during-gc-cache','valid-cache','valid-during-cache','referenced-cache','flush','after-gc-route')){
    & {
        $RouteRefresh=$case -ne 'cache';$CacheRetirePaths=if($case -ne 'route'){24576}else{0}
        if($case -eq 'unused-cache'){$RouteRefresh=$false;$CacheRetirePaths=49152}
        if($case -in @('during-gc-cache','valid-cache','valid-during-cache')){$RouteRefresh=$false}
        $ReferencedTcpPaths=0
        if($case -eq 'referenced-cache'){$RouteRefresh=$false;$CacheRetirePaths=1;$ReferencedTcpPaths=49152}
        $RetireDuringGc=$case -in @('during-gc-cache','valid-during-cache','referenced-cache')
        $KeepCacheValid=$case -in @('valid-cache','valid-during-cache','referenced-cache')
        if($case -eq 'cache'){$CacheRetirePaths=1}
        if($case -in @('flush','after-gc-route')){$CacheRetirePaths=0}
        $CacheInterfaceGuid=if($case -in @('unused-cache','during-gc-cache','valid-cache','valid-during-cache','referenced-cache')){'owned-guid'}else{''}
        $CacheInterfaceAlias=if($case -in @('unused-cache','during-gc-cache','valid-cache','valid-during-cache','referenced-cache')){'NetperfPath-123456abcdef'}else{''}
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
            if($case -in @('unused-cache','during-gc-cache','valid-cache','valid-during-cache','referenced-cache','flush')){
                if($endIndex -lt 0 -or $control.Arguments[$endIndex+1] -ne ($localOutput+'.gc.json')){
                    throw 'Unused-interface retirement must use the actual receiver GC-completion observation.'
                }
            }elseif($endIndex -ge 0){throw 'A non-unused-interface control changed its GC-start trigger.'}
            if(('-RetireDuringGc' -in $control.Arguments) -ne ($case -in @('during-gc-cache','valid-during-cache','referenced-cache'))){
                throw 'The actual control plan lost or leaked GC-active retirement selection.'
            }
            $referenceIndex=[Array]::IndexOf($control.Arguments,'-ReferencedTcpPaths')
            if(($referenceIndex -ge 0) -ne ($case -eq 'referenced-cache') -or
                ($referenceIndex -ge 0 -and $control.Arguments[$referenceIndex+1] -ne '49152')){
                throw 'The actual reference fixture lost its bounded pair count or leaked into another control.'
            }
            $populationIndex=[Array]::IndexOf($control.Arguments,'-PopulationInterfaceAlias')
            if($KeepCacheValid){
                if($populationIndex -lt 0 -or $control.Arguments[$populationIndex+1] -ne $alias -or
                    $control.Arguments[5] -ne $CacheInterfaceAlias){
                    throw 'Surviving paths must use the data interface while maintenance targets only the owned unused interface.'
                }
            }elseif($populationIndex -ge 0){throw 'Separate cache population leaked into a different control.'}
            if($case -eq 'flush' -and
                ((Split-Path $control.Arguments[3] -Leaf) -ne 'Invoke-ScopedDestinationCacheFlush.ps1' -or
                    '-NextHop' -in $control.Arguments -or '-ReceiverProcessId' -notin $control.Arguments)){
                throw 'The atomic destination-flush plan used a route mutation or lost receiver ownership.'
            }
            $populationGate=@($ast.FindAll({
                param($node)
                $node -is [Management.Automation.Language.IfStatementAst] -and
                    $node.Clauses[0].Item1.Extent.Text.StartsWith('$KeepCacheValid -and ($cacheReport.populationPlacement')
            },$true))
            if($populationGate.Count -ne 1){throw 'The actual surviving-population acceptance gate must be unique.'}
            $populationSettings=@($ast.FindAll({
                param($node)
                $node -is [Management.Automation.Language.AssignmentStatementAst] -and
                    $node.Left.Extent.Text -in @('$expectedPlacement','$expectedSockets')
            },$true))
            if($populationSettings.Count -ne 2){throw 'The actual population kind/count settings must be unique.'}
            $populationGateCode=(($populationSettings|Sort-Object {$_.Extent.StartOffset}|ForEach-Object{$_.Extent.Text})-join "`n")+"`n"+$populationGate[0].Extent.Text
            foreach($referenced in @($false,$true)){
            foreach($case in @('valid','wrong-placement','missing-references','changed-sources')){
                & {
                    $KeepCacheValid=$true;$CacheRetirePaths=if($referenced){1}else{24576}
                    $ReferencedTcpPaths=if($referenced){49152}else{0}
                    $cacheReport=[pscustomobject]@{populationPlacement=$(if($referenced){'surviving-referenced-loopback'}else{'surviving-data-interface'})
                        sourcePopulationPreserved=$true;heldSocketReferencesVerified=$true
                        heldSocketsAtVerification=$(if($referenced){98304}else{24576})}
                    if($case -eq 'wrong-placement'){$cacheReport.populationPlacement='retired-interface'}
                    if($case -eq 'missing-references'){$cacheReport.heldSocketsAtVerification=1}
                    if($case -eq 'changed-sources'){$cacheReport.sourcePopulationPreserved=$false}
                    $rejected=$false
                    try{& ([scriptblock]::Create($populationGateCode))}catch{
                        if($_.Exception.Message -notmatch 'valid-source data-interface population'){throw}
                        $rejected=$true
                    }
                    if($rejected -eq ($case -eq 'valid')){throw 'Surviving-cache evidence was accepted or rejected incorrectly.'}
                }
            }
            }
            $countIndex=[Array]::IndexOf($control.Arguments,'-PathCount')
            if($countIndex -ge 0 -and $control.Arguments[$countIndex+1] -ne [string]$CacheRetirePaths){
                throw 'The requested cache fixture count was changed during actual child argument transport.'
            }
        }
    }
}
$phaseValidation=@($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.IfStatementAst] -and
        $node.Clauses[0].Item1.Extent.Text -eq '$CacheInterfaceGuid' -and
        $node.Extent.Text.Contains('$retirementPhaseValid=')
},$true))
if($phaseValidation.Count -ne 1){throw 'The actual retirement phase acceptance gate must be identified.'}
foreach($case in @('during-valid','during-late','after-valid','after-early','held-after-valid','held-after-early','held-during-valid','held-during-late')){
    & {
        $CacheInterfaceGuid='owned-test-guid';$RetireDuringGc=$case -match 'during-'
        $KeepCacheValid=$case.StartsWith('held-')
        $origin=[datetime]'2026-01-01T00:00:00Z'
        $r=[pscustomobject]@{managedGc=[pscustomobject]@{collectionStartUtc=$origin;collectionEndUtc=$origin.AddSeconds(1)}}
        $apiStart=if($case -in @('during-valid','held-during-valid','after-early','held-after-early')){$origin.AddMilliseconds(200)}else{$origin.AddMilliseconds(1100)}
        $cacheReport=[pscustomobject]@{triggerPhase=$(if($KeepCacheValid -and $RetireDuringGc){'gc-active-held-valid-cache'}elseif($KeepCacheValid){'gc-complete-held-valid-cache'}elseif($RetireDuringGc){'gc-active-pre-released-cache'}else{'gc-complete-pre-released-cache'})
            snapshotCompletedUtc=$origin.AddMilliseconds(100);removeApiStartUtc=$apiStart;removeApiEndUtc=$origin.AddMilliseconds(1300)}
        $rejected=$false
        try{& ([scriptblock]::Create($phaseValidation[0].Extent.Text))}catch{
            if($case -in @('during-valid','after-valid','held-after-valid','held-during-valid') -or $_.Exception.Message -notmatch 'requested GC retirement phase'){throw}
            $rejected=$true
        }
        if($rejected -ne ($case -in @('during-late','held-during-late','after-early','held-after-early'))){throw 'GC-active and post-GC acceptance were conflated.'}
        if($case -in @('during-valid','held-during-valid') -and $cacheReport.collectionOverlapMilliseconds -ne 800){
            throw 'The actual collection/API overlap was not clipped to collection completion.'
        }
        $focus=@($ast.FindAll({
            param($node)
            $node -is [Management.Automation.Language.IfStatementAst] -and
                $node.Clauses[0].Item1.Extent.Text -eq '$SpinLocks -or $focusedCpuCapture'
        },$true))
        $selection=@($ast.FindAll({
            param($node)
            $node -is [Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left.Extent.Text -eq '$focusedCpuCapture'
        },$true))
        if($focus.Count -ne 1 -or $selection.Count -ne 1){throw 'Actual high-volume CPU capture selection must be unique.'}
        & {
            $NoTcpProbes=$true;$ExchangesPerConnection=1;$Connections=1024;$SpinLocks=$false
            $diagnostics='unused-owned-diagnostics';$cpuProfile='CPU';$profileArguments=@{}
            & ([scriptblock]::Create($selection[0].Extent.Text+"`n"+$focus[0].Extent.Text))
            if($profileArguments.KernelMode -ne 'SampledOnly'){throw 'CPU/CLR isolation must use focused sampling even at ordinary concurrency.'}
        }
        foreach($exchanges in @(1,64)){
            foreach($limit in @(1024,4096)){
                foreach($spin in @($false,$true)){
                    & {
                        $ExchangesPerConnection=$exchanges;$Connections=$limit;$SpinLocks=$spin
                        $diagnostics='unused-owned-diagnostics';$cpuProfile='CPU';$profileArguments=@{}
                        & ([scriptblock]::Create($selection[0].Extent.Text+"`n"+$focus[0].Extent.Text))
                        $expectedFocused=$exchanges -eq 64 -or $limit -gt 1024
                        if($expectedFocused){
                            $mode=if($spin){'SpinWithoutScheduling'}else{'SampledOnly'}
                            if($profileArguments.KernelMode -ne $mode -or -not $profileArguments.ContainsKey('KernelOutput')){
                                throw 'High-volume CPU capture did not select the bounded focused profile.'
                            }
                        }elseif($profileArguments.ContainsKey('KernelMode') -or
                            $profileArguments.ContainsKey('KernelOutput') -ne $spin){
                            throw 'Default ordinary CPU capture behavior changed.'
                        }
                    }
                }
            }
        }
    }
}
$wprFailure=@($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.IfStatementAst] -and
        $node.Clauses[0].Item1.Extent.Text -eq '$phase -eq ''wpr-exact-probe-start'''
},$true))
if($wprFailure.Count -ne 1){throw 'The actual bounded WPR failure diagnostic must be unique.'}
& {
    $phase='wpr-exact-probe-start';$diagnostics=[IO.Path]::GetTempPath();$probeStartup=@{}
    function Test-Path {[CmdletBinding()]param($LiteralPath) $true}
    function Get-Content {
        [CmdletBinding()]param($LiteralPath,[switch]$Raw)
        'The requested profile was not found. C:\private\synthetic-secret\sample.wprp'
    }
    & ([scriptblock]::Create($wprFailure[0].Extent.Text))
    $evidence=$probeStartup.wpr
    if($evidence.outputLogsPresent -ne 2 -or $evidence.rawMessagesExported -or
        'profile' -notin $evidence.publicDiagnosticTerms -or 'found' -notin $evidence.publicDiagnosticTerms -or
        ($evidence|ConvertTo-Json -Compress) -match 'private|synthetic-secret|sample\.wprp'){
        throw 'WPR diagnostics lost the public error terms or exported private raw text.'
    }
}
$wprStarts=@($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.CommandAst] -and
        $node.GetCommandName() -eq 'Invoke-TcpChurnTool' -and $node.Extent.Text.Contains("'-start'")
},$true))
$wprStop=@($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.IfStatementAst] -and
        $node.Clauses[0].Item1.Extent.Text -eq '$profileOwned'
},$true))
if($wprStarts.Count -ne 2 -or $wprStop.Count -ne 1){throw 'All actual recorder start/stop paths must be identified.'}
$restoration=@($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.ForEachStatementAst] -and
        $node.Condition.Extent.Text -eq '$pathControls'
},$true))
if($restoration.Count -ne 1 -or $wprStop[0].Extent.EndOffset -ge $restoration[0].Extent.StartOffset){
    throw 'Capture must close before signalling fixture teardown; restoration must still follow a failed stop.'
}
& {
    $wpr='unused-wpr';$cpuProfile='unused-cpu!CPU';$wprProfile='unused-probes.wprp'
    $diagnostics=Join-Path ([IO.Path]::GetTempPath()) ('uncreated-recorder-test-'+[guid]::NewGuid().ToString('N'))
    $PublishDirectory=$diagnostics;$analyzer='unused-analyzer'
    $wprInstance='NetperfGc-'+('1'*32)
    $simulateStopFailure=$false
    $calls=[Collections.Generic.List[object]]::new()
    function Invoke-TcpChurnTool {
        param($Program,$Arguments,$Directory,$LogPrefix,$TimeoutSeconds)
        $calls.Add([pscustomobject]@{Program=$Program;Arguments=$Arguments})
        if($simulateStopFailure -and $Arguments[0] -eq '-stop'){
            throw [Management.Automation.RuntimeException]::new('You cannot call a method on a null-valued expression.')
        }
    }
    foreach($start in $wprStarts){& ([scriptblock]::Create($start.Extent.Text))}
    foreach($call in $calls){
        if($call.Arguments[-2] -ne '-instancename' -or $call.Arguments[-1] -ne $wprInstance){
            throw 'Recorder start lost the owned instance or failed to place it last.'
        }
    }
    $calls.Clear()
    $profileOwned=$true;$focusedCpuCapture=$true;$WprProbes=$true;$wprStartAttempted=$true
    $cleanupErrors=[Collections.Generic.List[Exception]]::new()
    & ([scriptblock]::Create($wprStop[0].Extent.Text))
    if($calls.Count -ne 2 -or $calls[0].Arguments[0] -ne '--session-health' -or
        $calls[0].Arguments[-1] -ne $wprInstance -or $calls[1].Arguments[0] -ne '-stop' -or
        $calls[1].Arguments[-2] -ne '-instancename' -or $calls[1].Arguments[-1] -ne $wprInstance -or $cleanupErrors.Count){
        throw 'Recorder health or stop escaped the owning instance.'
    }
    $calls.Clear();$simulateStopFailure=$true
    & ([scriptblock]::Create($wprStop[0].Extent.Text))
    if($cleanupErrors.Count -ne 1 -or $cleanupErrors[0].Data['CleanupPhase'] -ne 'wpr-stop' -or
        -not $cleanupErrors[0].Data['CleanupErrorId'] -or $cleanupErrors[0].Data['CleanupOutputLogsPresent'] -ne 0){
        throw 'Recorder shutdown errors lost their bounded identity or were reported as success.'
    }
    $calls.Clear();$profileOwned=$false;$simulateStopFailure=$false
    & ([scriptblock]::Create($wprStop[0].Extent.Text))
    if($calls.Count -ne 1 -or $calls[0].Arguments[0] -ne '-cancel' -or
        $calls[0].Arguments[-2] -ne '-instancename' -or $calls[0].Arguments[-1] -ne $wprInstance){
        throw 'Partial-start cleanup must target only the new owned instance, never the default recording.'
    }
}
$metadata=@($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left.Extent.Text -eq '$result.probeCollectorBackend'
},$true))
if($metadata.Count -ne 1){throw 'Actual result recorder metadata must be unique.'}
& {
    $result=[ordered]@{};$WprProbes=$true;$SpinLocks=$false
    $siblings=@($metadata[0].Parent.Statements)
    $index=[Array]::IndexOf($siblings,$metadata[0])
    $commands=($siblings[$index..($index+2)]|ForEach-Object{$_.Extent.Text})-join "`n"
    & ([scriptblock]::Create($commands))
    if($result.probeCollectorBackend -ne 'wpr-exact-events' -or
        $result.recorderControlScope -ne 'unique-owned-named-instance' -or $result.kernelSpinlockEventsRequested){
        throw 'Actual recorder metadata augmentation failed or executed a bare command.'
    }
}
$cleanupTables=@($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.HashtableAst] -and
        @($node.KeyValuePairs|Where-Object{$_.Item1.Extent.Text -eq 'cleanupErrorFacts'}).Count -eq 1
},$true))
if($cleanupTables.Count -ne 1){throw 'The actual cleanup failure serialization must be unique.'}
& {
    $cleanupErrors=[Collections.Generic.List[Exception]]::new()
    $deadline=[Management.Automation.RuntimeException]::new('Test tool deadline exceeded.')
    $deadline.Data['CleanupPhase']='wpr-stop'
    $cleanupErrors.Add($deadline)
    $native=[InvalidOperationException]::new('Synthetic private C:\private\fixture-secret command failed.')
    $native.Data['ToolExitCode']=-1
    $cleanupErrors.Add($native)
    $pair=@($cleanupTables[0].KeyValuePairs|Where-Object{$_.Item1.Extent.Text -eq 'cleanupErrorFacts'})[0]
    $facts=@(& ([scriptblock]::Create($pair.Item2.Extent.Text)))
    if($facts.Count -ne 2 -or $facts[0].stage -ne 'wpr-stop' -or -not $facts[0].deadlineExceeded -or
        $facts[1].toolExitCode -ne -1 -or ($facts|ConvertTo-Json -Compress) -match 'private|fixture-secret'){
        throw 'Cleanup diagnostics lost the failure stage/code or leaked private exception text.'
    }
}
$tools=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'adapters\WindowsCts.psm1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
$invoke=@($tools.FindAll({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-TcpChurnTool'
},$true))
if($invoke.Count -ne 1){throw 'Actual bounded native-tool execution must be unique.'}
foreach($case in @('native-and-close','deadline-and-close','close-only','native-only','success')){
    & {
        $fixture=@{Closes=0}
        function Start-ChurnChild {
            param($Program,$Arguments,$Directory,$LogPrefix)
            $process=[pscustomobject]@{TimesOut=($case -eq 'deadline-and-close');ExitCode=$(if($case.StartsWith('native')){7}else{0})}
            $process|Add-Member ScriptMethod WaitForExit {param($Milliseconds) -not $this.TimesOut}
            @{Process=$process}
        }
        function Close-ChurnChild {
            param($Child)
            $fixture.Closes++
            if($case -in @('native-and-close','deadline-and-close','close-only')){throw [IO.IOException]::new('Synthetic owned cleanup failure.')}
        }
        . ([scriptblock]::Create($invoke[0].Extent.Text))
        $failure=$null;$value=$null
        try{$value=Invoke-TcpChurnTool -Program 'unused' -Arguments @('unused') -Directory 'unused' -LogPrefix 'unused' -TimeoutSeconds 1}
        catch{$failure=$_.Exception}
        if($fixture.Closes -ne 1){throw 'Native command cleanup was skipped or duplicated.'}
        if($case -in @('native-and-close','deadline-and-close')){
            if($failure -isnot [AggregateException] -or $failure.InnerExceptions.Count -ne 2 -or
                [bool]$failure.Data['PrimaryDeadlineExceeded'] -ne ($case -eq 'deadline-and-close') -or
                ($case -eq 'native-and-close' -and $failure.Data['ToolExitCode'] -ne 7)){
                throw 'Owned cleanup masked the primary native error or deadline.'
            }
        }elseif($case -eq 'native-only'){
            if($failure -isnot [InvalidOperationException] -or $failure.Data['ToolExitCode'] -ne 7){throw 'Native exit failure identity changed.'}
        }elseif($case -eq 'close-only'){
            if($failure -isnot [IO.IOException] -or $null -ne $value){throw 'Cleanup failure returned a success-shaped value.'}
        }elseif($null -ne $failure -or $value.ExitCode -ne 0){throw 'Successful native execution behavior changed.'}
    }
}
$noTcpSelection=@($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.IfStatementAst] -and
        $node.Clauses[0].Item1.Extent.Text -eq '$NoTcpProbes' -and
        $node.Extent.Text.Contains('$omittedTcpTasks=')
},$true))
$tcpAnalysis=@($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.IfStatementAst] -and
        $node.Clauses[0].Item1.Extent.Text -eq '-not $NoTcpProbes'
},$true))
if($noTcpSelection.Count -ne 1 -or $tcpAnalysis.Count -ne 1){throw 'Explicit TCP omission and analysis selection must be unique.'}
& {
    $NoTcpProbes=$true;$tasks=@('TcpTcbSynSend','TcpCloseTcbRequest')
    $omittedTcpTasks=@('TcpBlackHoleDetectionEntry');$tcpKeywords=[long]1
    . ([scriptblock]::Create($noTcpSelection[0].Extent.Text))
    if($tasks.Count -ne 0 -or $tcpKeywords -ne 0 -or $omittedTcpTasks.Count -ne 3){
        throw 'CPU/CLR isolation lost explicit omissions or still requested TCP events.'
    }
    function Invoke-TcpChurnTool {throw 'TCP analysis must not run when its provider was not recorded.'}
    function Read-TcpRecoveryEvidence {throw 'Missing TCP lifetime events must not be interpreted as measured zero counts.'}
    & ([scriptblock]::Create($tcpAnalysis[0].Extent.Text))
}
$slices=@($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.IfStatementAst] -and
        $node.Clauses[0].Item1.Extent.Text -eq '$CacheRetirePaths' -and
        $node.Extent.Text.Contains("File='cpu-cache-snapshot.json'")
},$true))
if($slices.Count -ne 1){throw 'The actual cache phase CPU plan must be unique.'}
foreach($case in @('sampled','no-samples','bad-window','lost')){
    & {
        $origin=([datetime]'2026-01-01T00:00:00Z').ToUniversalTime();$start=$origin.ToString('o');$endUtc=$origin.AddSeconds(2)
        $CacheRetirePaths=24576;$diagnostics='unused';$PublishDirectory='unused';$analyzer='unused'
        $cacheReport=[pscustomobject]@{snapshotStartedUtc=$origin.AddMilliseconds(200);snapshotCompletedUtc=$origin.AddMilliseconds(400)
            removeApiStartUtc=$origin.AddMilliseconds(600);removeApiEndUtc=$origin.AddMilliseconds(900)}
        if($case -eq 'bad-window'){$cacheReport.removeApiEndUtc=$origin.AddMilliseconds(500)}
        $calls=[Collections.Generic.List[object]]::new()
        function Invoke-TcpChurnTool {
            param($Program,$Arguments,$Directory,$LogPrefix,$TimeoutSeconds)
            $calls.Add([pscustomobject]@{Arguments=$Arguments})
        }
        function Get-Content {
            param($LiteralPath,[switch]$Raw)
            @{outcome=$(if($case -eq 'no-samples'){'no-samples'}else{'sampled'})
                eventsLost=$(if($case -eq 'lost'){1}else{0});unresolvedNetworkFrames=0}|ConvertTo-Json
        }
        $rejected=$false
        try{& ([scriptblock]::Create($slices[0].Extent.Text))}catch{
            if($_.Exception.Message -notmatch 'CPU phase must be positive|CPU phase failed lossless'){throw}
            $rejected=$true
        }
        if($rejected -ne ($case -in @('bad-window','lost'))){throw "Narrow-phase validity or loss gate changed: $case; rejected=$rejected."}
        if(-not $rejected -and ($calls.Count -ne 2 -or
            ([datetime]$calls[0].Arguments[2]).ToUniversalTime() -ne $cacheReport.snapshotStartedUtc -or
            ([datetime]$calls[0].Arguments[3]).ToUniversalTime() -ne $cacheReport.snapshotCompletedUtc -or
            ([datetime]$calls[1].Arguments[2]).ToUniversalTime() -ne $cacheReport.removeApiStartUtc -or
            ([datetime]$calls[1].Arguments[3]).ToUniversalTime() -ne $cacheReport.removeApiEndUtc)){
            throw 'Snapshot and maintenance CPU slices were conflated or clipped to a proxy interval.'
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
foreach($mode in @(@{Pressure=$false;Framed=$false},@{Pressure=$true;Framed=$false},
    @{Pressure=$false;Framed=$true},@{Pressure=$true;Framed=$true},@{Pressure=$false;Framed=$false;Core=$true},
    @{Pressure=$false;Framed=$false;Core=$true;Idle=$true},@{Pressure=$false;Framed=$false;Core=$true;Service=$true},
    @{Pressure=$false;Framed=$false;Core=$true;Service=$true;Pipelined=$true})){
    try{
        $pressureEnabled=$mode.Pressure;$framed=$mode.Framed;$coreMode=[bool]$mode.Core;$idleMode=[bool]$mode.Idle;$serviceMode=[bool]$mode.Service;$pipelinedMode=[bool]$mode.Pipelined
        $global:OwnedManagedGcPeer=@{}
        $peerChildren=[Collections.Generic.List[object]]::new()
        function Start-TcpChurnCollector {
            param($Program,$Arguments,$Directory,$LogPrefix,[switch]$CoreClr)
            $peerChildren.Add([pscustomobject]@{Arguments=$Arguments;CoreClr=[bool]$CoreClr})
            [pscustomobject]@{Process=$null}
        }
        & $peerLaunch[0].ScriptBlock.GetScriptBlock() 'unused-owned-root' '192.0.2.1' '192.0.2.2' 20300 4096 4096 $(if($serviceMode){512}else{1460}) $(if($serviceMode){512}else{1460}) 1024 $pressureEnabled $(if($idleMode){1}else{64}) $framed $coreMode $idleMode $serviceMode $pipelinedMode
        if($peerChildren.Count -ne $(if($pressureEnabled){2}else{1})){throw 'Optional pressure changed the ordinary peer launch count.'}
        if($peerChildren[0].Arguments.Count -ne 14 -or $peerChildren[0].CoreClr -ne $coreMode -or
            $peerChildren[0].Arguments[13] -ne $(if($pipelinedMode){'servicewait64:pipelined'}elseif($serviceMode){'servicewait64'}elseif($idleMode){'idlekeepalive'}elseif($framed){'exchanges:64:framed'}else{'exchanges:64'}) -or
            $peerChildren[0].Arguments[5] -ne $(if($serviceMode){'512'}else{'1460'}) -or
            $peerChildren[0].Arguments[11] -ne $(if($framed){'nagle'}else{'nodelay'})){
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
            'TcpCloseTcbRequest','TcpInsertConnectionTuple')){
            if($required -notin $tasks){throw 'Persistent selection lost required lifetime event coverage.'}
        }
        if($exchangeMode -eq 64 -and
            (($tcpKeywords -band [long]0x8100000084) -ne 0 -or $omittedTcpTasks.Count -ne 7 -or
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
$analysisTry=@($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.TryStatementAst] -and
        $node.Body.Extent.Text.Contains('$phase=''analyze-whole-cpu''') -and
        $node.Body.Extent.Text.Contains('$snapshotPaths=if($KeepCacheValid)')
},$true))
if($analysisTry.Count -ne 1){throw 'The actual public analysis and scenario gate must share one guarded block.'}
$gate=@($analysisTry[0].Body.Statements|Where-Object{
    $_ -is [Management.Automation.Language.IfStatementAst] -and
        $_.Extent.Text.Contains('$snapshotPaths=if($KeepCacheValid)')
})
if($gate.Count -ne 1){throw 'The actual scenario census gate must be unique.'}
$prefix=($analysisTry[0].Body.Statements|Where-Object{$_.Extent.StartOffset -le $gate[0].Extent.StartOffset}|
    ForEach-Object{$_.Extent.Text})-join "`n"
& {
    $CacheRetirePaths=98304;$KeepCacheValid=$true;$SpinLocks=$true
    $diagnostics='unused-owned-diagnostics';$PublishDirectory='unused-owned-publish';$cacheStem='route-control'
    $analyzer='unused-analyzer';$start='2026-01-01T00:00:00Z';$end='2026-01-01T00:01:00Z'
    $calls=[Collections.Generic.List[object]]::new()
    function Invoke-TcpChurnTool {param($Program,$Arguments,$Directory,$LogPrefix,$TimeoutSeconds)
        $calls.Add([pscustomobject]@{Arguments=$Arguments})
    }
    function Get-Content {param($Path,[switch]$Raw)
        '{"outcome":"failed","measuredHeldPathsAtSnapshot":0}'
    }
    $rejected=$false
    try{& ([scriptblock]::Create($prefix))}catch{
        if($_.Exception.Message -notmatch 'bounded source-retirement population'){throw}
        $rejected=$true
    }
    if(-not $rejected -or $calls.Count -ne 2 -or $calls[0].Arguments[1] -notlike '*cpu-load.json' -or
        $calls[1].Arguments[0] -ne '--spin-summary'){
        throw 'A rejected census either bypassed its failure gate or lost independent CPU/spin diagnostics.'
    }
}
$steadyLaunch=@($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.IfStatementAst] -and
        $node.Clauses[0].Item1.Extent.Text -eq '$SteadyStateFixture' -and
        $node.Extent.Text.Contains('Start-GcReceiverTraffic')
},$true))
$fixtureLaunch=@($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.IfStatementAst] -and
        $node.Clauses[0].Item1.Extent.Text -eq '$RouteRefresh -or $CacheRetirePaths'
},$true))
$completion=@($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left.Extent.Text -eq '$r' -and $node.Extent.Text.Contains('Complete-GcReceiverTraffic')
},$true))
if($steadyLaunch.Count -ne 1 -or $fixtureLaunch.Count -ne 1 -or $completion.Count -ne 1 -or
    $steadyLaunch[0].Extent.StartOffset -ge $fixtureLaunch[0].Extent.StartOffset){
    throw 'Steady-state producers must start before fixture construction with a separate completion phase.'
}
foreach($steady in @($false,$true)){
    & {
        $SteadyStateFixture=$steady;$receiverTrafficStarted=$false;$receiverState=@{}
        $calls=[Collections.Generic.List[string]]::new()
        function Start-GcReceiverTraffic {param($State);$calls.Add('start')}
        function Complete-GcReceiverTraffic {param($State);$calls.Add('complete')}
        function Invoke-GcReceiverTraffic {param($State);$calls.Add('legacy')}
        . ([scriptblock]::Create($steadyLaunch[0].Extent.Text))
        . ([scriptblock]::Create($completion[0].Extent.Text))
        if(($calls-join ',') -ne $(if($steady){'start,complete'}else{'legacy'})){
            throw 'The actual traffic dispatch duplicated or withheld a producer phase.'
        }
    }
}
$referenceGate=@($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.IfStatementAst] -and
        $node.Clauses[0].Item1.Extent.Text.StartsWith('$ReferencedTcpPaths -and ($cacheReport.pathReferenceKind')
},$true))
if($referenceGate.Count -ne 1){throw 'The actual referenced-path acceptance gate must be unique.'}
foreach($case in @('valid','wrong-kind','missing-preparation','missing-reservations','missing-paths','missing-pairs')){
    & {
        $ReferencedTcpPaths=49152
        $cacheReport=[pscustomobject]@{pathReferenceKind='established-loopback-tcp';requestedReferencedTcpPaths=49152
            referencedTcpPreparationQueries=49152;referencedTcpReservedSourcePorts=4096
            measuredReferencedTcpPathsAtSnapshot=49152;heldTcpConnectionPairsAtVerification=49152}
        if($case -eq 'wrong-kind'){$cacheReport.pathReferenceKind='socket-count-only'}
        if($case -eq 'missing-preparation'){$cacheReport.referencedTcpPreparationQueries=0}
        if($case -eq 'missing-reservations'){$cacheReport.referencedTcpReservedSourcePorts=0}
        if($case -eq 'missing-paths'){$cacheReport.measuredReferencedTcpPathsAtSnapshot=49151}
        if($case -eq 'missing-pairs'){$cacheReport.heldTcpConnectionPairsAtVerification=49151}
        $rejected=$false
        try{& ([scriptblock]::Create($referenceGate[0].Extent.Text))}catch{
            if($_.Exception.Message -notmatch 'actual referenced-path census'){throw}
            $rejected=$true
        }
        if($rejected -eq ($case -eq 'valid')){throw 'Referenced paths were accepted from socket counts or a different fixture kind.'}
    }
}
Write-Output 'Passed standalone/combined path plans and failure-safe companion cleanup; no network operations were performed.'
