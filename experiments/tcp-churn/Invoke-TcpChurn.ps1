# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TrafficExecutable,
    [Parameter(Mandatory)][string]$ClientAddress,
    [Parameter(Mandatory)][string]$ServerAddress,
    [Parameter(Mandatory)][string]$ClientInterface,
    [Parameter(Mandatory)][string]$ServerInterface,
    [Parameter(Mandatory)][string]$WorkDirectory,
    [int]$Port=53617,
    [int]$Connections=16,
    [int]$Seconds=15,
    [switch]$DedicatedAdapters
)
$ErrorActionPreference='Stop'
if (-not $DedicatedAdapters) { throw 'Acknowledge exclusive use of these adapters with -DedicatedAdapters.' }
Import-Module (Join-Path $PSScriptRoot 'TcpChurn.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'adapters\WindowsCts.psm1') -Force
if (Test-Path -LiteralPath $WorkDirectory) { throw 'Use a new work directory for each run.' }
$plan=New-TcpChurnPlan -ClientAddress $ClientAddress -ServerAddress $ServerAddress -Port $Port -Connections $Connections -Seconds $Seconds
New-Item -ItemType Directory -Path $WorkDirectory -ErrorAction Stop | Out-Null
$adapter=New-WindowsCtsAdapter -Executable $TrafficExecutable -DiagnosticsDirectory $WorkDirectory `
    -ClientInterface $ClientInterface -ServerInterface $ServerInterface
$result=Invoke-TcpChurnExperiment -Plan $plan -Adapter $adapter
$path=Join-Path $WorkDirectory 'result.json'
Export-TcpChurnPublicResult -Result $result -Path $path
Write-Output $path
