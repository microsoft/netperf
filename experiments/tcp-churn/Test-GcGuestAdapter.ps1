# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
$ErrorActionPreference='Stop'
$directory=Join-Path ([IO.Path]::GetTempPath()) ('gc-adapter-'+[guid]::NewGuid().ToString('N'))
$credential=[pscredential]::new('unused-test-account',(ConvertTo-SecureString 'unused-test-value' -AsPlainText -Force))
$checks=0
try {
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
    foreach($file in @('Invoke-ManagedGcPeerDiagnostic.ps1','Invoke-NetperfGuestTcpChurn.ps1')) {
        $tokens=$null;$errors=$null
        $null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot "adapters\$file"),[ref]$tokens,[ref]$errors)
        if($errors.Count){throw ($errors|Out-String)}
    }
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
