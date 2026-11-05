# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Destination,
    [string]$Manifest=(Join-Path $PSScriptRoot 'dependencies.json')
)
$ErrorActionPreference='Stop'
$lock=Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json
if ($lock.schema -ne 1) { throw 'Unknown dependency manifest.' }
foreach ($asset in $lock.assets) {
    if ($asset.file -notmatch '^[A-Za-z0-9_.-]+$' -or $asset.file -in @('.','..') -or
        [IO.Path]::GetExtension($asset.file) -notin @('.exe','.sys','.inf','.cat','.ps1') -or
        $asset.url -notmatch '^https://raw\.githubusercontent\.com/microsoft/(ctsTraffic|corenet-ci)/[a-f0-9]{40}/' -or
        $asset.sha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw 'Dependency is not an approved pinned public asset.' }
}
New-Item -ItemType Directory -Path $Destination -Force -ErrorAction Stop | Out-Null
foreach ($asset in $lock.assets) {
    $target=Join-Path $Destination $asset.file
    if (-not (Test-Path -LiteralPath $target)) { Invoke-WebRequest -Uri $asset.url -OutFile $target -ErrorAction Stop }
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $asset.sha256) {
        throw "Public dependency checksum mismatch: $($asset.file)"
    }
}
Write-Output ([IO.Path]::GetFullPath($Destination))
