# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
$ErrorActionPreference='Stop'
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
    foreach($extra in @(@{ManagedGcIsolatedData=$true},@{ManagedGcRecoveryMilliseconds=3000},@{ManagedGcHeapLayout='graph'},@{ManagedGcRouteVariant='peer-gateway'})) {
        $rejected=$false
        try {
            & (Join-Path $PSScriptRoot 'adapters\Invoke-NetperfGuestTcpChurn.ps1') `
                -VmName 'unused-test-only' -Credential $credential -PublishDirectory $directory @extra
        }catch {
            if($_.Exception.Message -notmatch 'Isolated data addresses require|Recovery duration selection requires|GC heap layout selection requires|Logical gateway selection requires'){throw}
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
    foreach($file in @('Invoke-ManagedGcPeerDiagnostic.ps1','Invoke-ManagedGcGuestEntry.ps1','Invoke-NetperfGuestTcpChurn.ps1','Invoke-ScopedNeighborPulse.ps1','Set-ScopedDataAddresses.ps1','GcReceiverTraffic.psm1','Invoke-ScopedPathRefresh.ps1','Invoke-ScopedPathRetirement.ps1')) {
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
    if($launch.Count -ne 1){throw 'The actual guest child launch call site must be uniquely identified.'}
    $actual=& {
        function Invoke-Command {
            [CmdletBinding()]
            param($Session,[scriptblock]$ScriptBlock,[object[]]$ArgumentList)
            Write-Output -NoEnumerate $ArgumentList
        }
        $session=$null;$guestRoot='unused-test-root';$Seconds=5;$Connections=1024;$ManagedGcPayloadBytes=2048
        $ProfileCpu=[switch]::new($true);$SynDrop=[switch]::new($false)
        $PeerMeasurement=[switch]::new($false);$ManagedGc=[switch]::new($true)
        $ManagedGcPeerRecovery=[switch]::new($true)
        $ManagedGcIsolatedData=[switch]::new($true);$ManagedGcRecoveryMilliseconds=3000
        $ManagedGcProcessRole='client'
        $ManagedGcHeapLayout='graph'
        $ManagedGcRouteRefresh=[switch]::new($true)
        $ManagedGcRouteVariant='peer-gateway'
        $ManagedGcReceiveBudgetBytes=16384
        $ManagedGcCacheRetirePaths=8192
        & ([scriptblock]::Create($launch[0].Extent.Text))
    }
    if($actual.Count -ne 18 -or $actual[16] -isnot [int] -or $actual[16] -ne 8192 -or
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
