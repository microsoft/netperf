# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('add','remove')][string]$Action,
    [Parameter(Mandatory)][string]$InterfaceAlias,
    [Parameter(Mandatory)][string]$Addresses,
    [Parameter(Mandatory)][string]$StateFile,
    [Parameter(Mandatory)][string]$ReportFile
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$plan=@($Addresses.Split(','))
if($plan.Count -lt 1 -or $plan.Count -gt 4 -or @($plan|Sort-Object -Unique).Count -ne $plan.Count){
    throw 'One to four unique owned data addresses are required.'
}
foreach($address in $plan) {
    if($address -notmatch '^198\.19\.240\.[1-6]$'){throw 'Only the dedicated benchmark /29 host addresses are permitted.'}
}
function Address-Number([string]$Address) {
    $ip=[Net.IPAddress]::Parse($Address)
    if($ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork){throw 'IPv4 routing evidence is required.'}
    [uint64]$number=0
    foreach($part in $ip.GetAddressBytes()){$number=($number -shl 8) -bor $part}
    $number
}
function Overlaps-DataPrefix([string]$Prefix) {
    $parts=$Prefix.Split('/')
    if($parts.Count -ne 2){throw 'A valid IPv4 route prefix is required.'}
    $length=[int]$parts[1]
    if($length -lt 0 -or $length -gt 32){throw 'The IPv4 route prefix length is invalid.'}
    if($length -eq 0){return $false}
    $compare=[Math]::Min($length,29)
    [uint64]$mask=(0xffffffffL -shl (32-$compare)) -band 0xffffffffL
    ((Address-Number $parts[0]) -band $mask) -eq ((Address-Number '198.19.240.0') -band $mask)
}
$nic=@(Get-NetAdapter -Name $InterfaceAlias -ErrorAction Stop)
if($nic.Count -ne 1){throw 'The owned data interface must be unique.'}
$network=@(Get-NetIPInterface -InterfaceIndex $nic[0].ifIndex -AddressFamily IPv4 -ErrorAction Stop)
if($network.Count -ne 1 -or [string]$network[0].Dhcp -ne 'Disabled'){
    throw 'Data aliases require an already-static interface; DHCP is never changed.'
}
function Read-AddressKeys {
    @(Get-NetIPAddress -InterfaceIndex $nic[0].ifIndex -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|
        ForEach-Object{"$($_.IPAddress)/$($_.PrefixLength)/$($_.SkipAsSource)"}|Sort-Object)
}
function Read-DefaultKeys {
    @(Get-NetRoute -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|
        Where-Object DestinationPrefix -eq '0.0.0.0/0'|
        ForEach-Object{"$($_.InterfaceIndex)/$($_.NextHop)/$($_.RouteMetric)"}|Sort-Object)
}
function Remove-OwnedAddresses {
    $saved=Import-Clixml -LiteralPath $StateFile -ErrorAction Stop
    if($saved.interfaceGuid -ne [string]$nic[0].InterfaceGuid -or
        ($saved.addresses -join ',') -ne ($plan -join ',') -or -not $saved.originalDhcpDisabled){
        throw 'The data-address snapshot does not match the owned plan and interface.'
    }
    foreach($address in $plan) {
        $rows=@(Get-NetIPAddress -InterfaceIndex $nic[0].ifIndex -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|
            Where-Object IPAddress -eq $address)
        if($rows.Count -gt 1){throw 'The owned data address is not unique.'}
        if($rows.Count) {
            if($rows[0].PrefixLength -ne 29 -or $rows[0].SkipAsSource -ne $true){
                throw 'An address no longer matches the owned fixture; refusing to remove it.'
            }
            Remove-NetIPAddress -InterfaceIndex $nic[0].ifIndex -IPAddress $address -PolicyStore ActiveStore -Confirm:$false -ErrorAction Stop
        }
    }
    $now=@(Get-NetIPInterface -InterfaceIndex $nic[0].ifIndex -AddressFamily IPv4 -ErrorAction Stop)
    if($now.Count -ne 1 -or [string]$now[0].Dhcp -ne 'Disabled' -or
        (@(Read-AddressKeys) -join '|') -ne (@($saved.originalAddressKeys) -join '|') -or
        (@(Read-DefaultKeys) -join '|') -ne (@($saved.originalDefaultKeys) -join '|')){
        throw 'Original management addresses, DHCP state or default routes did not verify.'
    }
    $left=@(Get-NetRoute -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|
        Where-Object{$_.DestinationPrefix -eq '198.19.240.0/29' -and $_.InterfaceIndex -eq $nic[0].ifIndex})
    if($left.Count){throw 'The owned connected data route remains after address cleanup.'}
}
if($Action -eq 'remove') {
    Remove-OwnedAddresses
    @{schema=1;removed=$true;ownedAddressCount=$plan.Count;managementPolicyPreserved=$true}|
        ConvertTo-Json|Set-Content -LiteralPath $ReportFile
    return
}
if(Test-Path -LiteralPath $StateFile){throw 'A fresh data-address ownership snapshot is required.'}
foreach($route in @(Get-NetRoute -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop)){
    if(Overlaps-DataPrefix $route.DestinationPrefix){throw 'An existing route overlaps the dedicated data prefix.'}
}
$all=@(Get-NetIPAddress -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop)
if(@($all|Where-Object{$_.IPAddress -match '^198\.19\.240\.[0-7]$'}).Count){throw 'The dedicated data prefix is already in use.'}
$original=@(Read-AddressKeys)
if(-not $original.Count){throw 'Existing management addressing must be preserved.'}
@{interfaceGuid=[string]$nic[0].InterfaceGuid;addresses=$plan;originalDhcpDisabled=$true
    originalAddressKeys=$original;originalDefaultKeys=@(Read-DefaultKeys)}|
    Export-Clixml -LiteralPath $StateFile -NoClobber
try {
    foreach($address in $plan) {
        $null=New-NetIPAddress -InterfaceIndex $nic[0].ifIndex -IPAddress $address -PrefixLength 29 `
            -SkipAsSource $true -PolicyStore ActiveStore -ErrorAction Stop
    }
    $wait=[Diagnostics.Stopwatch]::StartNew()
    do {
        $rows=@(Get-NetIPAddress -InterfaceIndex $nic[0].ifIndex -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|
            Where-Object{$_.IPAddress -in $plan})
        if(@($rows|Where-Object{[string]$_.AddressState -eq 'Duplicate'}).Count){throw 'A duplicate data address was detected.'}
        if($rows.Count -eq $plan.Count -and -not @($rows|Where-Object{[string]$_.AddressState -ne 'Preferred'}).Count){break}
        if($wait.Elapsed.TotalSeconds -gt 15){throw 'Owned data addresses did not become preferred.'}
        Start-Sleep -Milliseconds 100
    }while($true)
    if((@(Read-DefaultKeys) -join '|') -ne (@(Import-Clixml $StateFile).originalDefaultKeys -join '|')){
        throw 'Default routing changed while preparing the data fixture.'
    }
    $expected=@($original)+@($plan|ForEach-Object{"$_/29/True"})
    if((@(Read-AddressKeys) -join '|') -ne (@($expected|Sort-Object) -join '|')){
        throw 'Original management addresses did not verify after data-address preparation.'
    }
    @{schema=1;added=$true;ownedAddressCount=$plan.Count;skipAsSource=$true;managementPolicyPreserved=$true}|
        ConvertTo-Json|Set-Content -LiteralPath $ReportFile
}catch {
    $failure=$_
    try {Remove-OwnedAddresses}
    catch {throw [AggregateException]::new('Data-address preparation and rollback both failed.',[Exception[]]@($failure.Exception,$_.Exception))}
    throw $failure
}
