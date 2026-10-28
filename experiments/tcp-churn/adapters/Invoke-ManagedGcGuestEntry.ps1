# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CredentialFile,
    [Parameter(Mandatory)][string]$ScratchParent,
    [Parameter(Mandatory)][string]$PublishDirectory,
    [Parameter(Mandatory)][string]$AnalyzerDirectory,
    [int]$Seconds=5,
    [int]$Connections=256
)
$ErrorActionPreference='Stop'
if($PublishDirectory -ne (Join-Path $ScratchParent 'publish')) {
    throw 'The guest entry point requires its owned publication subdirectory.'
}
try {
    & (Join-Path $PSScriptRoot 'Invoke-ManagedGcPeerDiagnostic.ps1') @PSBoundParameters
} catch {
    $failure=$_
    $resultPath=Join-Path $PublishDirectory 'result.json'
    if(-not(Test-Path -LiteralPath $resultPath)) {
        if(-not(Test-Path -LiteralPath $PublishDirectory)) {
            $null=New-Item -ItemType Directory -Path $PublishDirectory -ErrorAction Stop
        }
        $id=[string]$failure.FullyQualifiedErrorId
        if($id -notmatch '^[A-Za-z0-9_.,-]{1,256}$'){$id='unclassified'}
        @{schema=1;workload='managed-gc-mixed';outcome='failed';phase='child-entry'
            failureType=$failure.Exception.GetType().FullName;failureCode=$failure.Exception.HResult
            errorId=$id;sourceLine=$failure.InvocationInfo.ScriptLineNumber
            conclusion='no-accepted-measurement'}|ConvertTo-Json|Set-Content -LiteralPath $resultPath
    }
    throw
}
