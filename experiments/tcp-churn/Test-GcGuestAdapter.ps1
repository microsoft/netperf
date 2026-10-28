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
} finally {
    if(Test-Path -LiteralPath $directory){Remove-Item -LiteralPath $directory -ErrorAction Stop}
}
Write-Output "Passed $checks managed-GC adapter preflight cases; no VM or network operations were performed."
