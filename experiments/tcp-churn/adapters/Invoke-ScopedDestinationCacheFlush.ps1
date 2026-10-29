# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InterfaceAlias,
    [Parameter(Mandatory)][string]$DataStateFile,
    [Parameter(Mandatory)][string]$StateFile,
    [Parameter(Mandatory)][string]$ReportFile,
    [string]$ReadyFile,[string]$BeginFile,[string]$EndFile,[string]$StopFile,
    [string]$ReceiverExecutable,[int]$ReceiverProcessId,
    [string]$ExpectedPeerMac,
    [switch]$RestoreOnly
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'WindowsCts.psm1')
function Invoke-OwnedDestinationFlush($Adapter,$Data,[Collections.IDictionary]$Report,[string]$Directory) {
    if([string]::IsNullOrWhiteSpace($Adapter.Name) -or $Adapter.ifIndex -lt 1 -or
        $Data.interfaceGuid -ne [string]$Adapter.InterfaceGuid -or -not $Data.originalDhcpDisabled -or
        '198.19.240.1' -notin @($Data.addresses) -or
        @($Data.addresses|Where-Object{$_ -notmatch '^198\.19\.240\.[1-4]$'}).Count){
        throw 'A destination flush requires the exact owned data interface and endpoint scope.'
    }
    foreach($destination in @('198.19.240.1','198.19.240.6')){
        $null=Invoke-TcpChurnTool -Program "$env:SystemRoot\System32\netsh.exe" `
            -Arguments @('interface','ipv4','delete','destinationcache',
                ('interface='+$Adapter.Name),('address='+$destination)) `
            -Directory $Directory -LogPrefix (Join-Path $Directory ('destination-flush-'+$Report.destinationFlushes)) -TimeoutSeconds 30
        $Report.destinationFlushes++
    }
}
function Read-Defaults {
    @(Get-NetRoute -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|
        Where-Object DestinationPrefix -eq '0.0.0.0/0'|
        ForEach-Object{"$($_.InterfaceIndex)/$($_.NextHop)/$($_.RouteMetric)"}|Sort-Object)
}
function Read-Addresses {
    @(Get-NetIPAddress -InterfaceIndex $adapter[0].ifIndex -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|
        ForEach-Object{"$($_.IPAddress)/$($_.PrefixLength)/$($_.SkipAsSource)"}|Sort-Object)
}
function Verify-NetworkSnapshot {
    $saved=Import-Clixml -LiteralPath $StateFile -ErrorAction Stop
    $current=@(Get-NetAdapter -Name $InterfaceAlias -ErrorAction Stop)
    $currentNetwork=@(Get-NetIPInterface -InterfaceIndex $adapter[0].ifIndex -AddressFamily IPv4 -ErrorAction Stop)
    if($saved.owner -ne 'tcp-churn-destination-flush-v1' -or $current.Count -ne 1 -or
        [string]$current[0].InterfaceGuid -ne $saved.interfaceGuid -or $current[0].ifIndex -ne $adapter[0].ifIndex -or
        $currentNetwork.Count -ne 1 -or [string]$currentNetwork[0].Dhcp -ne 'Disabled' -or
        (@(Read-Addresses)-join '|') -ne (@($saved.addresses)-join '|') -or
        (@(Read-Defaults)-join '|') -ne (@($saved.defaults)-join '|')){
        throw 'Destination-flush interface identity, addresses or default routing changed.'
    }
}
function Wait-GcSignal([string]$File) {
    $clock=[Diagnostics.Stopwatch]::StartNew()
    if(Test-Path -LiteralPath $StopFile){throw 'Traffic stopped before the destination-flush signal.'}
    while(-not(Test-Path -LiteralPath $File)){
        if(Test-Path -LiteralPath $StopFile){throw 'Traffic stopped before the destination-flush signal.'}
        if($clock.Elapsed.TotalSeconds -gt 60){throw 'The required real-GC signal did not reach the destination flush.'}
        Start-Sleep -Milliseconds 5
    }
}
$adapter=@(Get-NetAdapter -Name $InterfaceAlias -ErrorAction Stop)
if($adapter.Count -ne 1){throw 'The owned destination-flush interface must be unique.'}
$data=Import-Clixml -LiteralPath $DataStateFile -ErrorAction Stop
if($data.interfaceGuid -ne [string]$adapter[0].InterfaceGuid -or -not $data.originalDhcpDisabled -or
    '198.19.240.1' -notin @($data.addresses) -or
    @($data.addresses|Where-Object{$_ -notmatch '^198\.19\.240\.[1-4]$'}).Count){
    throw 'Destination flush requires the verified owned data-address fixture.'
}
if($RestoreOnly){
    Verify-NetworkSnapshot
    @{schema=1;networkConfigurationPreserved=$true}|ConvertTo-Json|Set-Content -LiteralPath $ReportFile
    return
}
if(!$ReadyFile -or !$BeginFile -or !$EndFile -or !$StopFile -or !$ReceiverExecutable -or $ReceiverProcessId -lt 1){
    throw 'Destination flush requires owned lifecycle files and the actual receiver identity.'
}
if(Test-Path -LiteralPath $StateFile){throw 'A fresh destination-flush snapshot is required.'}
$addresses=@(Get-NetIPAddress -InterfaceIndex $adapter[0].ifIndex -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|
    Where-Object{$_.IPAddress -in $data.addresses -and $_.PrefixLength -eq 29 -and $_.SkipAsSource})
$network=@(Get-NetIPInterface -InterfaceIndex $adapter[0].ifIndex -AddressFamily IPv4 -ErrorAction Stop)
$connected=@(Get-NetRoute -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|
    Where-Object{$_.DestinationPrefix -eq '198.19.240.0/29' -and $_.InterfaceIndex -eq $adapter[0].ifIndex -and $_.NextHop -eq '0.0.0.0'})
$peer=@(Get-NetNeighbor -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|
    Where-Object IPAddress -eq '198.19.240.6')
if($addresses.Count -ne @($data.addresses).Count -or $network.Count -ne 1 -or [string]$network[0].Dhcp -ne 'Disabled' -or
    $connected.Count -ne 1 -or [string]::IsNullOrWhiteSpace($ExpectedPeerMac) -or $peer.Count -ne 1 -or
    $peer[0].LinkLayerAddress -ne $ExpectedPeerMac -or
    (@(Read-Defaults)-join '|') -ne (@($data.originalDefaultKeys)-join '|')){
    throw 'Owned endpoints, peer identity and unchanged management routing must verify before a destination flush.'
}
$null=[Reflection.Assembly]::Load([IO.File]::ReadAllBytes($ReceiverExecutable))
@{owner='tcp-churn-destination-flush-v1';interfaceGuid=[string]$adapter[0].InterfaceGuid
    addresses=@(Read-Addresses);defaults=@(Read-Defaults)}|Export-Clixml -LiteralPath $StateFile -NoClobber
$report=[ordered]@{schema=1;scenario='owned-destination-cache-flush';scope='two-owned-data-destinations-only'
    destinationFlushes=0;networkConfigurationPreserved=$false;peerMacVerified=$true}
$failure=$null;$verifyFailure=$null
try{
    [IO.File]::WriteAllText($ReadyFile,'ready')
    Wait-GcSignal $BeginFile
    $report.snapshotStartedUtc=[DateTime]::UtcNow.ToString('o')
    $report.establishedAtSnapshot=[ArrivalTcp]::CountEstablishedConnections($ReceiverProcessId,20300)
    $report.snapshotCompletedUtc=[DateTime]::UtcNow.ToString('o')
    if($report.establishedAtSnapshot -lt 8 -or (Test-Path -LiteralPath $EndFile)){
        throw 'A live receiver cohort must verify while the actual GC is still running.'
    }
    Wait-GcSignal $EndFile
    if(Test-Path -LiteralPath $StopFile){throw 'Traffic stopped before destination-cache invalidation.'}
    $report.applyStartUtc=[DateTime]::UtcNow.ToString('o')
    Invoke-OwnedDestinationFlush $adapter[0] $data $report (Split-Path $StateFile)
    $report.applyEndUtc=[DateTime]::UtcNow.ToString('o')
}catch{$failure=$_}
finally{
    try{Verify-NetworkSnapshot;$report.networkConfigurationPreserved=$true}catch{$verifyFailure=$_}
    $report.outcome=if($null -eq $failure -and $null -eq $verifyFailure){'completed'}else{'failed'}
    if($null -ne $failure){
        $report.failureType=$failure.Exception.GetType().FullName
        if($failure.Exception.Data.Contains('ToolExitCode')){$report.toolExitCode=$failure.Exception.Data['ToolExitCode']}
    }
    if($null -ne $verifyFailure){$report.verificationFailureType=$verifyFailure.Exception.GetType().FullName}
    $report|ConvertTo-Json|Set-Content -LiteralPath $ReportFile
}
if($null -ne $failure -or $null -ne $verifyFailure){
    $exceptions=[Collections.Generic.List[Exception]]::new()
    if($null -ne $failure){$exceptions.Add($failure.Exception)}
    if($null -ne $verifyFailure){$exceptions.Add($verifyFailure.Exception)}
    throw [AggregateException]::new('The bounded owned-destination flush or configuration verification failed.',$exceptions)
}
