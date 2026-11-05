# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CredentialFile,
    [Parameter(Mandatory)][string]$ScratchParent,
    [Parameter(Mandatory)][string]$PublishDirectory,
    [Parameter(Mandatory)][string]$AnalyzerDirectory,
    [int]$Seconds=90,
    [int]$Connections=1024,
    [switch]$SynDrop
)
$ErrorActionPreference='Stop'
try { $credential=Import-Clixml -LiteralPath $CredentialFile -ErrorAction Stop }
finally { Remove-Item -LiteralPath $CredentialFile -ErrorAction Stop }
$peer=$null; $phase='peer-connect'; $success=$false
New-Item -ItemType Directory -Path $PublishDirectory -ErrorAction Stop|Out-Null
try {
    $peer=New-PSSession -ComputerName netperf-peer -Credential $credential -ConfigurationName PowerShell.7 -ErrorAction Stop
    $peerAddress=@([Net.Dns]::GetHostAddresses('netperf-peer')|Where-Object AddressFamily -eq InterNetwork)[0].ToString()
    $local=@(Find-NetRoute -RemoteIPAddress $peerAddress -ErrorAction Stop |
        Where-Object{$_.PSObject.Properties['IPAddress']})[0]
    $remote=Invoke-Command -Session $peer -ErrorAction Stop -ScriptBlock {
        param($address)
        if (@(Get-Process -Name 'Runner.Worker','ctsTraffic' -ErrorAction Ignore).Count) {throw 'Peer is busy.'}
        $ip=@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop|Where-Object IPAddress -eq $address)
        if($ip.Count -ne 1){throw 'Peer address is not uniquely owned.'}
        $root=Join-Path $env:TEMP ('tcp-churn-peer-'+[guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -ErrorAction Stop|Out-Null
        [pscustomobject]@{Root=$root;Interface=$ip[0].InterfaceAlias}
    } -ArgumentList $peerAddress
    $root=Split-Path $PSScriptRoot
    $tools=Join-Path $ScratchParent 'peer-tools'
    $logs=Join-Path $ScratchParent 'peer-diagnostics'
    New-Item -ItemType Directory -Path $logs -ErrorAction Stop|Out-Null
    $null=& (Join-Path $root 'Acquire-PublicTools.ps1') -Destination $tools
    Copy-Item -LiteralPath (Join-Path $tools 'ctsTraffic.exe') -Destination (Join-Path $remote.Root 'ctsTraffic.exe') -ToSession $peer -ErrorAction Stop
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'WindowsCts.psm1') -Destination (Join-Path $remote.Root 'WindowsCts.psm1') -ToSession $peer -ErrorAction Stop
    $phase='peer-cpu-measurement'
    & (Join-Path $root 'Invoke-CpuCampaign.ps1') -Tools $tools -Diagnostics $logs -PublishDirectory $PublishDirectory `
        -AnalyzerDirectory $AnalyzerDirectory -Seconds $Seconds -Connections $Connections -SynDrop:$SynDrop `
        -PeerSession $peer -PeerRoot $remote.Root -ClientInterface $local.InterfaceAlias -PeerInterface $remote.Interface `
        -FixedClientAddress $local.IPAddress -PeerAddress $peerAddress
    $success=$true
} catch {
    [ordered]@{schema=1;workload='tcp-churn';outcome='failed';phase=$phase;conclusion='no-measurement'} |
        ConvertTo-Json|Set-Content -LiteralPath (Join-Path $PublishDirectory 'result.json')
} finally {
    if($null -ne $peer){Remove-PSSession $peer -ErrorAction Stop}
}
if(-not $success){throw 'Real-peer measurement or required cleanup failed; inspect bounded published status.'}
