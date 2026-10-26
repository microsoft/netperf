# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$VmName,
    [Parameter(Mandatory)][pscredential]$Credential,
    [Parameter(Mandatory)][string]$PublishDirectory,
    [ValidateRange(5,120)][int]$Seconds=15,
    [ValidateRange(1,1024)][int]$Connections=16,
    [switch]$ProfileCpu,
    [string]$AnalyzerDirectory,
    [switch]$SynDrop,
    [switch]$ProbePeer,
    [switch]$PeerMeasurement
)
$ErrorActionPreference='Stop'
if (Test-Path -LiteralPath $PublishDirectory) { throw 'Use a new publication directory.' }
New-Item -ItemType Directory -Path $PublishDirectory -ErrorAction Stop | Out-Null
$session=$null; $guestRoot=$null; $phase='guest-connect'; $success=$false
try {
    if ((Get-VM -Name $VmName -ErrorAction Stop).State -ne 'Running') {
        throw 'The documented guest must already be running; this adapter does not reset other workloads.'
    }
    $session=New-PSSession -VMName $VmName -Credential $Credential -ErrorAction Stop
    if ($ProbePeer) {
        $phase='peer-connectivity'
        $peerResult=Invoke-Command -Session $session -ErrorAction Stop -ScriptBlock {
            param($credential)
            if (@(Get-Process -Name 'Runner.Worker','ctsTraffic' -ErrorAction Ignore).Count) { throw 'Client guest is busy.' }
            $peer=New-PSSession -ComputerName netperf-peer -Credential $credential -ConfigurationName PowerShell.7 -ErrorAction Stop
            try {
                $peerCpus=Invoke-Command -Session $peer -ErrorAction Stop -ScriptBlock {
                    if (@(Get-Process -Name 'Runner.Worker','ctsTraffic' -ErrorAction Ignore).Count) { throw 'Peer guest is busy.' }
                    (Get-CimInstance Win32_Processor | Measure-Object NumberOfLogicalProcessors -Sum).Sum
                }
                [pscustomobject]@{schema=1;peerConnected=$true;peerLogicalProcessors=[int]$peerCpus;conclusion='connectivity-only'}
            } finally { Remove-PSSession $peer -ErrorAction Stop }
        } -ArgumentList $Credential
        $peerResult|Select-Object schema,peerConnected,peerLogicalProcessors,conclusion|ConvertTo-Json |
            Set-Content -LiteralPath (Join-Path $PublishDirectory 'peer-check.json') -Encoding utf8
        return
    }
    $phase='guest-idle-check'
    $guestRoot=Invoke-Command -Session $session -ErrorAction Stop -ScriptBlock {
        if (@(Get-Process -Name 'Runner.Worker','ctsTraffic' -ErrorAction Ignore).Count) {
            throw 'Guest has an active Actions worker or CTS process.'
        }
        $root=Join-Path $env:TEMP ('netperf-churn-'+[guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -ErrorAction Stop | Out-Null
        $root
    }
    $phase='guest-copy'
    $localRoot=Split-Path $PSScriptRoot
    $remoteRoot=Join-Path $guestRoot 'experiment'
    $null=Invoke-Command -Session $session -ErrorAction Stop -ScriptBlock {
        param($path)
        New-Item -ItemType Directory -Path (Join-Path $path 'adapters') -Force -ErrorAction Stop | Out-Null
    } -ArgumentList $remoteRoot
    foreach ($file in @('TcpChurn.psm1','Acquire-PublicTools.ps1','dependencies.json','Invoke-CpuCampaign.ps1')) {
        Copy-Item -LiteralPath (Join-Path $localRoot $file) -Destination (Join-Path $remoteRoot $file) -ToSession $session -ErrorAction Stop
    }
    if ($ProfileCpu) {
        Copy-Item -LiteralPath $AnalyzerDirectory -Destination (Join-Path $guestRoot 'analyzer') `
            -Recurse -ToSession $session -ErrorAction Stop
    }
    foreach ($file in @('WindowsCts.psm1','Invoke-NetperfTcpChurn.ps1','Invoke-NetperfPeerCpu.ps1')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination (Join-Path $remoteRoot "adapters\$file") -ToSession $session -ErrorAction Stop
    }
    $phase='guest-traffic'
    $exit=Invoke-Command -Session $session -ErrorAction Stop -ScriptBlock {
        param($root,$seconds,$connections,$profile,$synDrop,$peerMeasurement,$credential)
        if (@(Get-Process -Name 'Runner.Worker','ctsTraffic' -ErrorAction Ignore).Count) {
            throw 'Guest became busy before traffic setup.'
        }
        $program=Join-Path $root 'experiment\adapters\Invoke-NetperfTcpChurn.ps1'
        # Native diagnostics remain inside the guest, never in public logs/artifacts.
        $extra=@()
        $credentialFile=$null
        if ($peerMeasurement) {
            $program=Join-Path $root 'experiment\adapters\Invoke-NetperfPeerCpu.ps1'
            $credentialFile=Join-Path $root 'peer-credential.clixml'
            # DPAPI-protected for this same account/machine; child deletes it immediately on import.
            $credential|Export-Clixml -LiteralPath $credentialFile -ErrorAction Stop
            $extra=@('-CredentialFile',$credentialFile,'-AnalyzerDirectory',(Join-Path $root 'analyzer'))
        } else {
            $extra=@('-DedicatedLab')
            if ($profile) { $extra+=@('-ProfileCpu','-AnalyzerDirectory',(Join-Path $root 'analyzer')) }
        }
        if ($synDrop) { $extra+='-SynDrop' }
        try {
            & pwsh -NoProfile -NonInteractive -File $program -ScratchParent $root `
                -PublishDirectory (Join-Path $root 'publish') -Seconds $seconds `
                -Connections $connections @extra *> (Join-Path $root 'adapter.log')
            $LASTEXITCODE
        } finally {
            if($credentialFile -and (Test-Path -LiteralPath $credentialFile)){Remove-Item -LiteralPath $credentialFile -ErrorAction Stop}
        }
    } -ArgumentList $guestRoot,$Seconds,$Connections,[bool]$ProfileCpu,[bool]$SynDrop,[bool]$PeerMeasurement,$Credential
    $phase='guest-result'
    $remoteResult=Join-Path $guestRoot 'publish\result.json'
    Copy-Item -LiteralPath $remoteResult -Destination (Join-Path $PublishDirectory 'result.json') -FromSession $session -ErrorAction Stop
    if ($ProfileCpu) {
        foreach ($file in @('cpu-idle.json','cpu-load.json','cpu-progress.json','tcp-state.json','tcp-events.json')) {
            $remoteFile=Join-Path $guestRoot "publish\$file"
            if (Invoke-Command -Session $session -ScriptBlock {param($p) Test-Path -LiteralPath $p -PathType Leaf} -ArgumentList $remoteFile) {
                Copy-Item -LiteralPath $remoteFile -Destination (Join-Path $PublishDirectory $file) `
                    -FromSession $session -ErrorAction Stop
            }
        }
    }
    $result=Get-Content -LiteralPath (Join-Path $PublishDirectory 'result.json') -Raw | ConvertFrom-Json
    $expected=if($SynDrop){'observed-syn-failures'}else{'collected'}
    if ($exit -ne 0 -or $result.outcome -ne $expected) { throw 'Guest experiment or cleanup did not succeed.' }
    $success=$true
} catch {
    if (-not (Test-Path -LiteralPath (Join-Path $PublishDirectory 'result.json'))) {
        [ordered]@{schema=1;workload='tcp-churn';outcome='failed';phase=$phase;conclusion='no-measurement'} |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PublishDirectory 'result.json') -Encoding utf8
    }
} finally {
    if ($null -ne $session) { Remove-PSSession $session -ErrorAction Stop }
}
if (-not $success) { throw "Dedicated guest experiment failed at $phase; no host/runner configuration was changed." }
Write-Output 'Real netperf guest traffic and owned fixture cleanup completed.'
