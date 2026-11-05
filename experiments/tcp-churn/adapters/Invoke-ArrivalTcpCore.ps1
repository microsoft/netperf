# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory,Position=0)][string]$ExecutablePath,
    [Parameter(Position=1,ValueFromRemainingArguments)][string[]]$WorkloadArguments
)
$ErrorActionPreference='Stop'
if([object].Assembly.GetName().Name -ne 'System.Private.CoreLib' -or -not [Runtime.GCSettings]::IsServerGC){
    throw 'The CoreCLR workload requires process-local server GC configured before startup.'
}
if(-not(Test-Path -LiteralPath $ExecutablePath -PathType Leaf) -or $WorkloadArguments.Count -lt 7){
    throw 'The CoreCLR workload requires its compiled public assembly and complete bounded arguments.'
}
$assembly=[Reflection.Assembly]::Load([IO.File]::ReadAllBytes($ExecutablePath))
$entry=$assembly.EntryPoint
if($null -eq $entry -or $entry.ReturnType -ne [int]){
    throw 'The compiled public workload must expose its integer entry point.'
}
$code=$entry.Invoke($null,@(,[string[]]$WorkloadArguments))
exit $code
