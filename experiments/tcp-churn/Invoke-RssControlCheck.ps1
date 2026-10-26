# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AdapterName,
    [Parameter(Mandatory)][string]$PublishFile,
    [ValidateRange(1,128)][int]$ExpectedProcessors=128,
    [ValidateRange(1,128)][int]$ExpectedQueues=128
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'RssControl.psm1') -Force
if(Test-Path -LiteralPath $PublishFile) { throw 'Use a new result file.' }
$phase='read'
try {
    foreach($attempt in 1..2) {
        $settings=@(Get-NetAdapterRss -Name $AdapterName -ErrorAction Stop|Where-Object Name -ceq $AdapterName)
        if($settings.Count -ne 1) { throw 'Select exactly one adapter by its literal name.' }
        $phase='validate'
        $result=Assert-RssControlPath -Settings $settings[0] -ExpectedProcessors $ExpectedProcessors -ExpectedQueues $ExpectedQueues
        if($attempt -eq 1) { Start-Sleep -Seconds 1;$phase='reread' }
    }
    $result|ConvertTo-Json -Depth 3|Set-Content -LiteralPath $PublishFile -Encoding utf8
} catch {
    [ordered]@{schema=1;expectedProcessors=$ExpectedProcessors;expectedQueues=$ExpectedQueues;phase=$phase
        controlPathVerified=$false;adapterConfigurationChanged=$false;conclusion='not-validated'} |
        ConvertTo-Json|Set-Content -LiteralPath $PublishFile -Encoding utf8
    throw
}
