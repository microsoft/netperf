# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InterfaceAlias,
    [Parameter(Mandatory)][string]$LocalAddress,
    [Parameter(Mandatory)][string]$PeerAddress,
    [Parameter(Mandatory)][string]$ExpectedMac,
    [Parameter(Mandatory)][string]$StateFile,
    [Parameter(Mandatory)][string]$ReportFile,
    [string]$ReadyFile,
    [string]$TrafficReadyFile,
    [string]$StopFile,
    [ValidateRange(1,65535)][int]$Port=20300,
    [ValidateRange(100,8000)][int]$DurationMilliseconds=8000,
    [switch]$RestoreOnly
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
foreach($address in @($LocalAddress,$PeerAddress)) {
    $parsed=[Net.IPAddress]::Parse($address)
    if($parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or [Net.IPAddress]::IsLoopback($parsed)) {
        throw 'The scoped pulse requires non-loopback IPv4 endpoints.'
    }
}
if($LocalAddress -eq $PeerAddress){throw 'The scoped pulse requires distinct endpoints.'}
if(-not $RestoreOnly -and (!$ReadyFile -or !$TrafficReadyFile -or !$StopFile)){
    throw 'The scoped pulse requires its owned readiness and graceful-stop files.'
}
Import-Module (Join-Path $PSScriptRoot 'WindowsCts.psm1') -Force
function Normalize-Mac([string]$Value) {
    $value=$Value.Replace(':','-').ToUpperInvariant()
    if($value -notmatch '^(?:[0-9A-F]{2}-){5}[0-9A-F]{2}$' -or
        $value -eq '00-00-00-00-00-00' -or ([Convert]::ToByte($value.Substring(0,2),16) -band 1)){
        throw 'A nonzero unicast MAC is required.'
    }
    $value
}
$ExpectedMac=Normalize-Mac $ExpectedMac
$adapter=@(Get-NetAdapter -Name $InterfaceAlias -ErrorAction Stop)
if($adapter.Count -ne 1){throw 'The client data adapter must be unique.'}
$substitute=Normalize-Mac $adapter[0].MacAddress
if($substitute -eq $ExpectedMac){throw 'The substitute must be the owned client MAC, distinct from the verified peer.'}
$addresses=@(Get-NetIPAddress -InterfaceIndex $adapter[0].ifIndex -AddressFamily IPv4 -ErrorAction Stop|
    Where-Object IPAddress -eq $LocalAddress)
$interfaces=@(Get-NetIPInterface -InterfaceIndex $adapter[0].ifIndex -AddressFamily IPv4 -ErrorAction Stop)
if($addresses.Count -ne 1 -or $interfaces.Count -ne 1 -or [string]$interfaces[0].Forwarding -ne 'Disabled'){
    throw 'A unique owned client IPv4 address with forwarding disabled is required.'
}
function Read-Neighbor {
    @(Get-NetNeighbor -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|
        Where-Object IPAddress -eq $PeerAddress)
}
function Set-Neighbor([string]$Mac) {
    $null=Invoke-TcpChurnTool -Program "$env:SystemRoot\System32\netsh.exe" `
        -Arguments @('interface','ipv4','set','neighbors',$InterfaceAlias,$PeerAddress,$Mac,'store=active') `
        -Directory (Split-Path $ReportFile) -LogPrefix ($ReportFile+'.netsh-'+[guid]::NewGuid().ToString('N')) -TimeoutSeconds 10
    $current=@(Read-Neighbor)
    if($current.Count -ne 1 -or (Normalize-Mac $current[0].LinkLayerAddress) -ne $Mac){
        throw 'The owned neighbor change did not verify.'
    }
}
function Restore-Neighbor {
    $saved=Import-Clixml -LiteralPath $StateFile -ErrorAction Stop
    if($saved.interfaceGuid -ne [string]$adapter[0].InterfaceGuid -or
        $saved.localAddress -ne $LocalAddress -or $saved.peerAddress -ne $PeerAddress -or
        $saved.expectedMac -ne $ExpectedMac -or $saved.substituteMac -ne $substitute -or -not $saved.originalDynamic){
        throw 'The neighbor snapshot does not match the owned endpoints and adapter.'
    }
    $current=@(Read-Neighbor)
    if($current.Count -gt 1){throw 'The owned neighbor is not unique.'}
    if($current.Count) {
        $mac=[string]$current[0].LinkLayerAddress
        if(-not [string]::IsNullOrWhiteSpace($mac) -and $mac -ne '00-00-00-00-00-00' -and
            (Normalize-Mac $mac) -notin @($ExpectedMac,$substitute)){
            throw 'The neighbor changed to an unowned MAC; refusing to overwrite another actor.'
        }
        if([string]$current[0].State -eq 'Permanent' -or $mac -ne $ExpectedMac) {
            Set-Neighbor $ExpectedMac
            Remove-NetNeighbor -InterfaceAlias $InterfaceAlias -IPAddress $PeerAddress -PolicyStore ActiveStore -Confirm:$false -ErrorAction Stop
        }
    }
    $remaining=@(Read-Neighbor)
    if(@($remaining|Where-Object{[string]$_.State -eq 'Permanent' -or $_.LinkLayerAddress -eq $substitute}).Count){
        throw 'The temporary static neighbor was not removed.'
    }
}
if($RestoreOnly) {
    Restore-Neighbor
    @{schema=1;restored=$true;scope='owned-peer-only'}|ConvertTo-Json|Set-Content -LiteralPath $ReportFile
    return
}
if(Test-Path -LiteralPath $StateFile){throw 'The scoped pulse requires a fresh ownership snapshot.'}
$original=@(Read-Neighbor)
if($original.Count -ne 1 -or [string]$original[0].State -eq 'Permanent' -or
    (Normalize-Mac $original[0].LinkLayerAddress) -ne $ExpectedMac){
    throw 'The verified peer must have one existing dynamic neighbor.'
}
@{interfaceGuid=[string]$adapter[0].InterfaceGuid;localAddress=$LocalAddress;peerAddress=$PeerAddress
    expectedMac=$ExpectedMac;substituteMac=$substitute;originalDynamic=$true}|Export-Clixml -LiteralPath $StateFile -NoClobber
$changed=$false;$failure=$null;$restoreFailure=$null
$report=[ordered]@{schema=1;scenario='owned-peer-stale-neighbor-recovery';requestedMilliseconds=$DurationMilliseconds
    establishedAtTrigger=0;applied=$false;restored=$false;scope='owned-peer-only';firewallChanged=$false;linkDisabled=$false}
$phase='await-traffic'
try {
    $baseline=Get-NetAdapterStatistics -Name $InterfaceAlias -ErrorAction Stop
    [IO.File]::WriteAllText($ReadyFile,'ready')
    $wait=[Diagnostics.Stopwatch]::StartNew()
    $pattern='^\s*TCP\s+'+[regex]::Escape($LocalAddress)+':\d+\s+'+[regex]::Escape($PeerAddress)+':'+$Port+'\s+ESTABLISHED\s*$'
    do {
        if(Test-Path -LiteralPath $StopFile){throw 'The workload stopped before the scoped pulse.'}
        if(Test-Path -LiteralPath $TrafficReadyFile) {
            $phase='await-established-data'
            $stats=Get-NetAdapterStatistics -Name $InterfaceAlias -ErrorAction Stop
            if($stats.SentBytes-$baseline.SentBytes -ge 65536) {
                $table=& "$env:SystemRoot\System32\netstat.exe" -an -p tcp
                if($LASTEXITCODE){throw 'The established data cohort could not be verified.'}
                $cohort=@($table|Where-Object{$_ -match $pattern}).Count
                if($cohort -ge 8){$report.establishedAtTrigger=$cohort;break}
            }
        }
        if($wait.Elapsed.TotalSeconds -gt 45){throw 'No established owned data cohort reached the pulse threshold.'}
        Start-Sleep -Milliseconds 50
    }while($true)
    if(Test-Path -LiteralPath $StopFile){throw 'The workload stopped before applying the scoped pulse.'}
    $phase='apply'
    $report.applyStartUtc=[DateTime]::UtcNow.ToString('o')
    $changed=$true
    Set-Neighbor $substitute
    $report.applied=$true
    $report.appliedUtc=[DateTime]::UtcNow.ToString('o')
    $phase='blackout'
    $hold=[Diagnostics.Stopwatch]::StartNew()
    while($hold.Elapsed.TotalMilliseconds -lt $DurationMilliseconds) {
        if(Test-Path -LiteralPath $StopFile){throw 'The workload stopped during the scoped pulse.'}
        Start-Sleep -Milliseconds 50
    }
    $report.verifiedHoldMilliseconds=$hold.Elapsed.TotalMilliseconds
}catch{$failure=$_}
finally {
    try {
        if($changed) {
            $report.restoreStartUtc=[DateTime]::UtcNow.ToString('o')
            Restore-Neighbor
            $report.restoredUtc=[DateTime]::UtcNow.ToString('o')
        }
        $report.restored=$true
    }catch{$restoreFailure=$_}
    $report.phase=$phase
    if($null -ne $failure) {
        $report.failureType=$failure.Exception.GetType().FullName
        $report.failureCode=$failure.Exception.HResult
        $report.toolExitCode=if($failure.Exception.Data.Contains('ToolExitCode')){$failure.Exception.Data['ToolExitCode']}else{$null}
    }
    if($null -ne $restoreFailure){$report.restoreFailureType=$restoreFailure.Exception.GetType().FullName}
    $report.outcome=if($null -eq $failure -and $null -eq $restoreFailure){'recovered'}else{'failed'}
    $report|ConvertTo-Json|Set-Content -LiteralPath $ReportFile
}
if($null -ne $failure -or $null -ne $restoreFailure) {
    $errors=[Collections.Generic.List[Exception]]::new()
    if($null -ne $failure){$errors.Add($failure.Exception)}
    if($null -ne $restoreFailure){$errors.Add($restoreFailure.Exception)}
    throw [AggregateException]::new('The scoped neighbor pulse or required restoration failed.',$errors)
}
