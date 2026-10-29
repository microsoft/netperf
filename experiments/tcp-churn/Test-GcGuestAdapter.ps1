# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
$ErrorActionPreference='Stop'
$workflowText=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\.github\workflows\tcp-churn-guest.yml') -Raw
foreach($name in @('cpu-cache-snapshot.json','cpu-cache-maintenance.json')){
    if(@([regex]::Matches($workflowText,('(?m)^\s+\$\{\{ runner\.temp \}\}/tcp-churn-guest-.*?/'+[regex]::Escape($name)+'\s*$'))).Count -ne 1){
        throw 'A generated cache CPU phase is missing or duplicated in the actual artifact upload allowlist.'
    }
}
$directory=Join-Path ([IO.Path]::GetTempPath()) ('gc-adapter-'+[guid]::NewGuid().ToString('N'))
$credential=[pscredential]::new('unused-test-account',(ConvertTo-SecureString 'unused-test-value' -AsPlainText -Force))
$checks=0
try {
    Import-Module (Join-Path $PSScriptRoot 'adapters\WindowsCts.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'adapters\GcReceiverTraffic.psm1') -Force
    foreach($name in @('Invoke-TcpChurnTool','Start-TcpChurnCollector','Stop-TcpChurnCollector')){
        if($null -eq (Get-Command $name -ErrorAction Stop)){throw 'Receiver-module import invalidated shared lifecycle commands.'}
    }
    $checks++
    foreach($case in @('no-profile','syn-drop','peer-probe','peer-measurement')) {
        $extra=@{ManagedGc=$true}
        if($case -ne 'no-profile'){$extra.ProfileCpu=$true}
        switch($case) {
            syn-drop {$extra.SynDrop=$true}
            peer-probe {$extra.ProbePeer=$true}
            peer-measurement {$extra.PeerMeasurement=$true}
        }
        $rejected=$false
        try {
            & (Join-Path $PSScriptRoot 'adapters\Invoke-NetperfGuestTcpChurn.ps1') `
                -VmName 'unused-test-only' -Credential $credential -PublishDirectory $directory @extra
        }catch {
            if($_.Exception.Message -notmatch 'Managed-GC diagnostics require CPU profiling'){throw}
            $rejected=$true
        }
        if(-not $rejected -or (Test-Path -LiteralPath $directory)){throw "GC adapter preflight mutated state or accepted invalid mode: $case"}
        $checks++
    }
    $rejected=$false
    try {
        & (Join-Path $PSScriptRoot 'adapters\Invoke-NetperfGuestTcpChurn.ps1') `
            -VmName 'unused-test-only' -Credential $credential -PublishDirectory $directory -ManagedGcPayloadBytes 2048
    }catch {
        if($_.Exception.Message -notmatch 'Managed-GC payload selection requires'){throw}
        $rejected=$true
    }
    if(-not $rejected -or (Test-Path -LiteralPath $directory)){throw 'Payload selection outside managed-GC mode mutated state or was accepted.'}
    $checks++
    $rejected=$false
    try {
        & (Join-Path $PSScriptRoot 'adapters\Invoke-NetperfGuestTcpChurn.ps1') `
            -VmName 'unused-test-only' -Credential $credential -PublishDirectory $directory -Seconds 1
    }catch {
        if($_.Exception.Message -notmatch 'Intervals below five seconds require'){throw}
        $rejected=$true
    }
    if(-not $rejected -or (Test-Path -LiteralPath $directory)){throw 'A short interval outside managed-GC mode mutated state or was accepted.'}
    $checks++
    $rejected=$false
    try {
        & (Join-Path $PSScriptRoot 'adapters\Invoke-NetperfGuestTcpChurn.ps1') `
            -VmName 'unused-test-only' -Credential $credential -PublishDirectory $directory -ManagedGcPeerRecovery
    }catch {
        if($_.Exception.Message -notmatch 'Peer recovery requires managed-GC'){throw}
        $rejected=$true
    }
    if(-not $rejected -or (Test-Path -LiteralPath $directory)){throw 'Peer recovery outside managed-GC mode mutated state or was accepted.'}
    $checks++
    foreach($extra in @(@{ManagedGcIsolatedData=$true},@{ManagedGcRecoveryMilliseconds=3000},@{ManagedGcHeapLayout='graph'},@{ManagedGcRouteVariant='peer-gateway'},@{ManagedGcWprProbes=$true},@{ManagedGcRssProcessors=64},@{ManagedGcOwnedDataInterface=$true})) {
        $rejected=$false
        try {
            & (Join-Path $PSScriptRoot 'adapters\Invoke-NetperfGuestTcpChurn.ps1') `
                -VmName 'unused-test-only' -Credential $credential -PublishDirectory $directory @extra
        }catch {
            if($_.Exception.Message -notmatch 'Isolated data addresses require|Recovery duration selection requires|GC heap layout selection requires|Logical gateway selection requires|Exact WPR probes require|Scoped RSS requires|Disposable data transport requires'){throw}
            $rejected=$true
        }
        if(-not $rejected -or (Test-Path -LiteralPath $directory)){throw 'Invalid data-fixture or recovery-duration selection mutated state.'}
        $checks++
    }
    foreach($extra in @(@{ManagedGcProcessRole='server'},@{ManagedGc=$true;ProfileCpu=$true;ManagedGcProcessRole='server'},
        @{ManagedGc=$true;ProfileCpu=$true;ManagedGcProcessRole='server';ManagedGcIsolatedData=$true;ManagedGcPeerRecovery=$true})) {
        $rejected=$false
        try {
            & (Join-Path $PSScriptRoot 'adapters\Invoke-NetperfGuestTcpChurn.ps1') `
                -VmName 'unused-test-only' -Credential $credential -PublishDirectory $directory @extra
        }catch {
            if($_.Exception.Message -notmatch 'Receiver GC requires'){throw}
            $rejected=$true
        }
        if(-not $rejected -or (Test-Path $directory)){throw 'Invalid receiver-GC mode mutated state or was accepted.'}
        $checks++
    }
    foreach($extra in @(@{ManagedGcRouteRefresh=$true},@{ManagedGc=$true;ProfileCpu=$true;ManagedGcRouteRefresh=$true})) {
        $rejected=$false
        try {
            & (Join-Path $PSScriptRoot 'adapters\Invoke-NetperfGuestTcpChurn.ps1') `
                -VmName 'unused-test-only' -Credential $credential -PublishDirectory $directory @extra
        }catch {
            if($_.Exception.Message -notmatch 'Route refresh requires'){throw}
            $rejected=$true
        }
        if(-not $rejected -or (Test-Path $directory)){throw 'Invalid route-control mode mutated state or was accepted.'}
        $checks++
    }
    foreach($extra in @(@{ManagedGcReceiveBudgetBytes=16384},
        @{ManagedGc=$true;ProfileCpu=$true;ManagedGcReceiveBudgetBytes=16384})){
        $rejected=$false
        try {
            & (Join-Path $PSScriptRoot 'adapters\Invoke-NetperfGuestTcpChurn.ps1') `
                -VmName 'unused-test-only' -Credential $credential -PublishDirectory $directory @extra
        }catch{
            if($_.Exception.Message -notmatch 'bounded receive budget requires receiver-GC'){throw}
            $rejected=$true
        }
        if(-not $rejected -or (Test-Path $directory)){throw 'Invalid receive-budget mode mutated state or was accepted.'}
        $checks++
    }
    foreach($extra in @(@{ManagedGcCacheRetirePaths=1024},
        @{ManagedGc=$true;ProfileCpu=$true;ManagedGcCacheRetirePaths=1024})){
        $rejected=$false
        try {
            & (Join-Path $PSScriptRoot 'adapters\Invoke-NetperfGuestTcpChurn.ps1') `
                -VmName 'unused-test-only' -Credential $credential -PublishDirectory $directory @extra
        }catch{
            if($_.Exception.Message -notmatch 'Cache retirement requires isolated receiver-GC'){throw}
            $rejected=$true
        }
        if(-not $rejected -or (Test-Path $directory)){throw 'Invalid cache-retirement mode mutated state or was accepted.'}
        $checks++
    }
    foreach($extra in @(@{ManagedGcPeerPressure=$true},@{ManagedGc=$true;ProfileCpu=$true;ManagedGcPeerPressure=$true})){
        $rejected=$false
        try {
            & (Join-Path $PSScriptRoot 'adapters\Invoke-NetperfGuestTcpChurn.ps1') `
                -VmName 'unused-test-only' -Credential $credential -PublishDirectory $directory @extra
        }catch{
            if($_.Exception.Message -notmatch 'Peer GC pressure requires isolated receiver-GC'){throw}
            $rejected=$true
        }
        if(-not $rejected -or (Test-Path $directory)){throw 'Invalid companion-GC mode mutated state or was accepted.'}
        $checks++
    }
    $rejected=$false
    try {
        & (Join-Path $PSScriptRoot 'adapters\Invoke-NetperfGuestTcpChurn.ps1') `
            -VmName 'unused-test-only' -Credential $credential -PublishDirectory $directory -ManagedGcUnusedInterface
    }catch{
        if($_.Exception.Message -notmatch 'Unused-interface retirement requires bounded'){throw}
        $rejected=$true
    }
    if(-not $rejected -or (Test-Path $directory)){throw 'Invalid disposable-interface mode mutated state or was accepted.'}
    $checks++
    $rejected=$false
    try {
        & (Join-Path $PSScriptRoot 'adapters\Invoke-NetperfGuestTcpChurn.ps1') `
            -VmName 'unused-test-only' -Credential $credential -PublishDirectory $directory -ManagedGcSpinLocks
    }catch{
        if($_.Exception.Message -notmatch 'Owned spinlock capture requires managed-GC'){throw}
        $rejected=$true
    }
    if(-not $rejected -or (Test-Path $directory)){throw 'Invalid spinlock mode mutated state or was accepted.'}
    $checks++
    $rejected=$false
    try{
        & (Join-Path $PSScriptRoot 'adapters\Invoke-NetperfGuestTcpChurn.ps1') `
            -VmName 'unused-test-only' -Credential $credential -PublishDirectory $directory `
            -ManagedGc -ProfileCpu -ManagedGcExchanges 64
    }catch{
        if($_.Exception.Message -notmatch 'Persistent exchanges require receiver-GC mode'){throw}
        $rejected=$true
    }
    if(-not $rejected -or (Test-Path -LiteralPath $directory)){throw 'Invalid persistent mode mutated state or was accepted.'}
    $checks++
    $rejected=$false
    try{
        & (Join-Path $PSScriptRoot 'adapters\Invoke-NetperfGuestTcpChurn.ps1') `
            -VmName 'unused-test-only' -Credential $credential -PublishDirectory $directory -Connections 4096
    }catch{
        if($_.Exception.Message -notmatch 'High concurrency requires receiver-GC mode'){throw}
        $rejected=$true
    }
    if(-not $rejected -or (Test-Path -LiteralPath $directory)){throw 'Unbounded high-concurrency mode mutated state or was accepted.'}
    $checks++
    $rejected=$false
    try{
        & (Join-Path $PSScriptRoot 'adapters\Invoke-NetperfGuestTcpChurn.ps1') `
            -VmName 'unused-test-only' -Credential $credential -PublishDirectory $directory -ManagedGcKeepCacheValid
    }catch{
        if($_.Exception.Message -notmatch 'Surviving cache population requires the owned unused-interface control'){throw}
        $rejected=$true
    }
    if(-not $rejected -or (Test-Path -LiteralPath $directory)){throw 'Unowned surviving-cache mode mutated state or was accepted.'}
    $checks++
    $rejected=$false
    try{
        & (Join-Path $PSScriptRoot 'adapters\Invoke-NetperfGuestTcpChurn.ps1') `
            -VmName 'unused-test-only' -Credential $credential -PublishDirectory $directory -ManagedGcNoTcpProbes
    }catch{
        if($_.Exception.Message -notmatch 'CPU/CLR-only diagnosis requires'){throw}
        $rejected=$true
    }
    if(-not $rejected -or (Test-Path -LiteralPath $directory)){throw 'Invalid CPU/CLR-only mode mutated state or was accepted.'}
    $checks++
    $rejected=$false
    try{
        & (Join-Path $PSScriptRoot 'adapters\Invoke-NetperfGuestTcpChurn.ps1') `
            -VmName 'unused-test-only' -Credential $credential -PublishDirectory $directory -ManagedGcFramedNagle
    }catch{
        if($_.Exception.Message -notmatch 'Framed Nagle exchanges require'){throw}
        $rejected=$true
    }
    if(-not $rejected -or (Test-Path -LiteralPath $directory)){throw 'Invalid framed-pacing mode mutated state or was accepted.'}
    $checks++
    foreach($extra in @(@{ManagedGcCacheRetirePaths=1024},@{ManagedGcPeerPressure=$true})){
        $rejected=$false
        try{
            & (Join-Path $PSScriptRoot 'adapters\Invoke-NetperfGuestTcpChurn.ps1') `
                -VmName 'unused-test-only' -Credential $credential -PublishDirectory $directory `
                -ManagedGc -ProfileCpu -ManagedGcIsolatedData -ManagedGcProcessRole server `
                -ManagedGcRouteRefresh -ManagedGcRouteVariant destination-flush @extra
        }catch{
            if($_.Exception.Message -notmatch 'GC-completion path refresh requires an isolated control'){throw}
            $rejected=$true
        }
        if(-not $rejected -or (Test-Path -LiteralPath $directory)){throw 'A confounded destination flush mutated state or was accepted.'}
        $checks++
    }
    foreach($file in @('Invoke-ManagedGcPeerDiagnostic.ps1','Invoke-ManagedGcGuestEntry.ps1','Invoke-NetperfGuestTcpChurn.ps1','Invoke-ScopedNeighborPulse.ps1','Set-ScopedDataAddresses.ps1','GcReceiverTraffic.psm1','Invoke-ScopedPathRefresh.ps1','Invoke-ScopedPathRetirement.ps1','New-GcProbeWprProfile.ps1','Invoke-ScopedDestinationCacheFlush.ps1')) {
        $tokens=$null;$errors=$null
        $parsed=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot "adapters\$file"),[ref]$tokens,[ref]$errors)
        if($errors.Count){throw ($errors|Out-String)}
        if($file -eq 'Invoke-NetperfGuestTcpChurn.ps1'){$guestAst=$parsed}
    }
    $launch=@($guestAst.FindAll({
        param($node)
        if($node -isnot [Management.Automation.Language.CommandAst] -or $node.GetCommandName() -ne 'Invoke-Command'){return $false}
        foreach($element in $node.CommandElements) {
            if($element -is [Management.Automation.Language.ScriptBlockExpressionAst] -and
                'managedGc' -in @($element.ScriptBlock.ParamBlock.Parameters.Name.VariablePath.UserPath)){return $true}
        }
        return $false
    },$true))
    $manifestInit=@($guestAst.FindAll({
        param($node)
        $node -is [Management.Automation.Language.AssignmentStatementAst] -and
            $node.Left.Extent.Text -eq '$adapterFiles' -and
            $node.Operator -eq [Management.Automation.Language.TokenKind]::Equals
    },$true))
    $manifestManaged=@($guestAst.FindAll({
        param($node)
        $node -is [Management.Automation.Language.IfStatementAst] -and
            $node.Clauses[0].Item1.Extent.Text -eq '$ManagedGc' -and $node.Extent.Text.Contains('$adapterFiles+=')
    },$true))
    if($manifestInit.Count -ne 1 -or $manifestManaged.Count -ne 1){throw 'The actual guest deployment manifest must be identified.'}
    & {
        $ManagedGc=$true
        . ([scriptblock]::Create($manifestInit[0].Extent.Text+"`n"+$manifestManaged[0].Extent.Text))
        foreach($required in @('WindowsCts.psm1','Invoke-ManagedGcPeerDiagnostic.ps1','Invoke-ManagedGcGuestEntry.ps1',
            'Invoke-ScopedPathRefresh.ps1','Invoke-ScopedPathRetirement.ps1','Invoke-ScopedDestinationCacheFlush.ps1',
            'GcReceiverTraffic.psm1','New-GcProbeWprProfile.ps1','Set-ScopedRss.ps1')){
            if($required -notin $adapterFiles){throw 'A launchable managed-GC control was omitted from actual guest deployment.'}
        }
    }
    $checks++
    if($launch.Count -ne 1){throw 'The actual guest child launch call site must be uniquely identified.'}
    $outerTry=@($guestAst.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.TryStatementAst]})
    if($outerTry.Count -ne 1 -or -not $outerTry[0].Finally.Extent.Text.Contains('$rssAttempted') -or
        $launch[0].Extent.Text.Contains('$rssAttempted')){
        throw 'RSS rollback must remain in the owning host scope, not the remote child startup finally.'
    }
    $rssSelectors=@($guestAst.FindAll({
        param($node)
        $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Select-Object' -and
            $node.Extent.Text.Contains('actualProcessorArrayCount')
    },$true))
    if($rssSelectors.Count -ne 2){throw 'Both existing and disposable RSS failure serializers must be exercised.'}
    foreach($selector in $rssSelectors){
        & {
            $fixture=[pscustomobject]@{schema=1;actualProcessorArrayCount=40
                actualSettings=@{MaxNumber=38;MaxGroup=1};requestedSettings=@{MaxNumber=39;MaxGroup=1}
                PSComputerName='unpublishable-test-host';RunspaceId='unpublishable-test-identity'}
            $selected=& ([scriptblock]::Create('$fixture | '+$selector.Extent.Text))
            if($selected.actualSettings.MaxNumber -ne 38 -or $selected.requestedSettings.MaxNumber -ne 39 -or
                'PSComputerName' -in $selected.PSObject.Properties.Name -or 'RunspaceId' -in $selected.PSObject.Properties.Name){
                throw 'The actual RSS serializer dropped setting diagnostics or retained remoting identity.'
            }
        }
        $checks++
    }
    $actual=& {
        function Invoke-Command {
            [CmdletBinding()]
            param($Session,[scriptblock]$ScriptBlock,[object[]]$ArgumentList)
            Write-Output -NoEnumerate $ArgumentList
        }
        $session=$null;$guestRoot='unused-test-root';$Seconds=5;$Connections=4096;$ManagedGcPayloadBytes=2048
        $ProfileCpu=[switch]::new($true);$SynDrop=[switch]::new($false)
        $PeerMeasurement=[switch]::new($false);$ManagedGc=[switch]::new($true)
        $ManagedGcPeerRecovery=[switch]::new($true)
        $ManagedGcIsolatedData=[switch]::new($true);$ManagedGcRecoveryMilliseconds=3000
        $ManagedGcProcessRole='client'
        $ManagedGcExchanges=64
        $ManagedGcRetireDuringGc=[switch]::new($true)
        $ManagedGcKeepCacheValid=[switch]::new($true)
        $ManagedGcNoTcpProbes=[switch]::new($true)
        $ManagedGcFramedNagle=[switch]::new($true)
        $ManagedGcHeapLayout='graph'
        $ManagedGcRouteRefresh=[switch]::new($true)
        $ManagedGcRouteVariant='peer-gateway'
        $ManagedGcReceiveBudgetBytes=16384
        $ManagedGcCacheRetirePaths=8192
        $ManagedGcWprProbes=[switch]::new($true)
        $ManagedGcPeerPressure=[switch]::new($true)
        $fixtureAlias='NetperfPath-123456abcdef'
        $fixtureGuid='11111111-2222-3333-4444-555555555555'
        $ManagedGcSpinLocks=[switch]::new($true)
        $dataAlias='NetperfData-abcdef123456'
        $dataGuid='66666666-7777-8888-9999-000000000000'
        & ([scriptblock]::Create($launch[0].Extent.Text))
    }
    if($actual.Count -ne 30 -or $actual[29] -isnot [bool] -or -not $actual[29] -or
        $actual[28] -isnot [bool] -or -not $actual[28] -or
        $actual[27] -isnot [bool] -or -not $actual[27] -or
        $actual[2] -ne 4096 -or $actual[26] -isnot [bool] -or -not $actual[26] -or
        $actual[25] -isnot [int] -or $actual[25] -ne 64 -or
        $actual[22] -ne 'NetperfData-abcdef123456' -or
        $actual[23] -ne '66666666-7777-8888-9999-000000000000' -or
        $actual[21] -isnot [bool] -or -not $actual[21] -or
        $actual[19] -ne 'NetperfPath-123456abcdef' -or
        $actual[20] -ne '11111111-2222-3333-4444-555555555555' -or
        $actual[18] -isnot [bool] -or -not $actual[18] -or
        $actual[17] -isnot [bool] -or -not $actual[17] -or
        $actual[16] -isnot [int] -or $actual[16] -ne 8192 -or
        $actual[15] -isnot [int] -or $actual[15] -ne 16384 -or
        $actual[14] -ne 'peer-gateway' -or $actual[13] -isnot [bool] -or -not $actual[13] -or
        $actual[12] -ne 'graph' -or $actual[11] -ne 'client' -or $actual[7] -ne 2048 -or $actual[8] -isnot [bool] -or -not $actual[8] -or
        $actual[9] -isnot [bool] -or -not $actual[9] -or $actual[10] -ne 3000 -or
        $actual[3] -isnot [bool] -or -not $actual[3] -or
        $actual[4] -isnot [bool] -or $actual[4] -or $actual[5] -isnot [bool] -or $actual[5] -or
        $actual[6] -isnot [bool] -or -not $actual[6]){
        throw 'The actual guest launch must transport Boolean mode flags, not truthy literal strings.'
    }
    $checks++
    $null=New-Item -ItemType Directory -Path $directory
    $publish=Join-Path $directory 'publish'
    $rejected=$false
    try {
        & (Join-Path $PSScriptRoot 'adapters\Invoke-ManagedGcPeerDiagnostic.ps1') `
            -CredentialFile (Join-Path $directory 'absent.clixml') -ScratchParent $directory `
            -PublishDirectory $publish -AnalyzerDirectory (Join-Path $directory 'unused-analyzer')
    }catch {
        if($_.Exception.Message -notmatch 'Managed-GC diagnostic or required cleanup failed'){throw}
        $rejected=$true
    }
    $status=Get-Content (Join-Path $publish 'result.json') -Raw|ConvertFrom-Json
    if(-not $rejected -or $status.outcome -ne 'failed' -or $status.phase -ne 'credential-import' -or
        [string]::IsNullOrWhiteSpace($status.failureType) -or -not $status.cleanupVerified -or
        $status.cleanupErrorCount -ne 0){throw 'Initialization failure was not explicitly and safely reported.'}
    $checks++
    Remove-Item -LiteralPath (Join-Path $publish 'result.json')
    $rejected=$false
    try {
        & (Join-Path $PSScriptRoot 'adapters\Invoke-ManagedGcGuestEntry.ps1') `
            -CredentialFile (Join-Path $directory 'absent.clixml') -ScratchParent $directory `
            -PublishDirectory $publish -AnalyzerDirectory (Join-Path $directory 'unused-analyzer') -Seconds 0
    }catch {
        if($_.FullyQualifiedErrorId -notmatch 'ParameterArgumentValidationError'){throw}
        $rejected=$true
    }
    $status=Get-Content (Join-Path $publish 'result.json') -Raw|ConvertFrom-Json
    if(-not $rejected -or $status.outcome -ne 'failed' -or $status.phase -ne 'child-entry' -or
        $status.failureType -notmatch 'ParameterBindingValidationException' -or
        $status.errorId -notmatch 'ParameterArgumentValidationError'){
        throw 'Child startup failure was not explicitly and safely reported.'
    }
    $checks++
    $probeTry=@($guestAst.FindAll({
        param($node)
        $node -is [Management.Automation.Language.TryStatementAst] -and
            @($node.Body.Statements|Where-Object{$_.Extent.Text.StartsWith('$query=Start-Process')}).Count -eq 1
    },$true))
    if($probeTry.Count -ne 1){throw 'The actual read-only WPR query must be uniquely identified.'}
    foreach($recording in @($false,$true)){
        & {
            $probeOut=Join-Path $directory 'wpr.out';$probeErr=Join-Path $directory 'wpr.err'
            $fixture=@{handleRead=$false;recording=$recording}
            function Start-Process {
                [CmdletBinding()]
                param($FilePath,$ArgumentList,$RedirectStandardOutput,$RedirectStandardError,[switch]$PassThru,[switch]$NoNewWindow)
                if($ArgumentList -ne '-status'){throw 'The probe must not modify recording state.'}
                [IO.File]::WriteAllText($RedirectStandardOutput,$(if($fixture.recording){"Profiles:`r`n    CPU.Verbose.File"}else{'WPR is not recording'}))
                [IO.File]::WriteAllText($RedirectStandardError,'')
                $fake=[pscustomobject]@{}
                $fake|Add-Member ScriptProperty Handle {$fixture.handleRead=$true;[intptr]1}
                $fake|Add-Member ScriptProperty ExitCode {if($fixture.handleRead){0}else{$null}}
                $fake|Add-Member ScriptMethod WaitForExit {param($milliseconds) if($null -ne $milliseconds){$true}}
                $fake|Add-Member ScriptMethod Refresh {}
                $fake
            }
            . ([scriptblock]::Create($probeTry[0].Extent.Text))
            if($wprExit -isnot [int] -or $wprExit -ne 0 -or $wprCpu -ne $recording -or $wprNotRunning -eq $recording -or
                (Test-Path -LiteralPath $probeOut) -or (Test-Path -LiteralPath $probeErr)){
                throw 'The actual WPR query lost its exit code, misclassified status or leaked temporary files.'
            }
        }
        $checks++
    }
} finally {
    if(Test-Path -LiteralPath $directory) {
        $result=Join-Path $directory 'publish\result.json'
        if(Test-Path -LiteralPath $result){Remove-Item -LiteralPath $result -ErrorAction Stop}
        foreach($child in @('publish','managed-gc-diagnostics')) {
            $path=Join-Path $directory $child
            if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -ErrorAction Stop}
        }
        Remove-Item -LiteralPath $directory -ErrorAction Stop
    }
}
Write-Output "Passed $checks managed-GC adapter preflight cases; no VM or network operations were performed."
