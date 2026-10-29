# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CredentialFile,
    [Parameter(Mandatory)][string]$ScratchParent,
    [Parameter(Mandatory)][string]$PublishDirectory,
    [Parameter(Mandatory)][string]$AnalyzerDirectory,
    [int]$Seconds=5,
    [int]$Connections=256,
    [int]$PayloadBytes=65536,
    [switch]$PeerRecovery,
    [switch]$IsolatedData,
    [int]$RecoveryMilliseconds=8000,
    [ValidateSet('client','server')][string]$GcProcessRole='client',
    [ValidateSet('arrays','graph')][string]$HeapLayout='arrays',
    [switch]$RouteRefresh,
    [ValidateSet('onlink','peer-gateway')][string]$RouteVariant='onlink',
    [ValidateSet(0,16384)][int]$ReceiveBudgetBytes=0,
    [ValidateSet(0,1024,8192,24576)][int]$CacheRetirePaths=0,
    [switch]$WprProbes,
    [switch]$PeerGcPressure,
    [string]$CacheInterfaceAlias,
    [string]$CacheInterfaceGuid,
    [switch]$SpinLocks
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
