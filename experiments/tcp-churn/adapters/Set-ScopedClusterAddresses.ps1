# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('add','remove')][string]$Action,
    [Parameter(Mandatory)][string]$InterfaceAlias,
    [Parameter(Mandatory)][ValidateSet(64,256,1000)][int]$Count,
    [Parameter(Mandatory)][string]$StateFile,
    [Parameter(Mandatory)][string]$ReportFile
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$prefixFirst=([uint64]198 -shl 24) -bor ([uint64]19 -shl 16) -bor ([uint64]64 -shl 8);$prefixLast=$prefixFirst+1023
function Get-ClusterAddress([int]$Ordinal) {
    "198.19.$(64+[Math]::Floor(($Ordinal-1)/250)).$(1+(($Ordinal-1)%250))"
}
$plan=@(1..$Count|ForEach-Object{Get-ClusterAddress $_})
function Address-Number([string]$Address) {
    [uint64]$number=0
    foreach($part in [Net.IPAddress]::Parse($Address).GetAddressBytes()){$number=($number -shl 8) -bor $part}
    $number
}
function Test-PrefixOverlap([string]$Prefix) {
    $parts=$Prefix.Split('/')
    if($parts.Count -ne 2 -or $parts[0].Contains(':')){return $false}
    $length=[int]$parts[1]
    if($length -eq 0){return $false}
    $size=[uint64][Math]::Pow(2,32-$length);$first=(Address-Number $parts[0]);$first-=$first%$size
    $first -le $prefixLast -and ($first+$size-1) -ge $prefixFirst
}
$nic=@(Get-NetAdapter -Name $InterfaceAlias -ErrorAction Stop)
if($nic.Count -ne 1){throw 'The owned data interface must be unique.'}
$network=@(Get-NetIPInterface -InterfaceIndex $nic[0].ifIndex -AddressFamily IPv4 -ErrorAction Stop)
if($network.Count -ne 1 -or [string]$network[0].Dhcp -ne 'Disabled'){throw 'Cluster aliases require an already-static interface.'}
function Read-OtherAddressKeys {
    @(Get-NetIPAddress -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|
        Where-Object{-not((Address-Number $_.IPAddress) -ge $prefixFirst -and (Address-Number $_.IPAddress) -le $prefixLast)}|
        ForEach-Object{"$($_.InterfaceIndex)/$($_.IPAddress)/$($_.PrefixLength)"}|Sort-Object)
}
function Read-DefaultKeys {
    @(Get-NetRoute -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|Where-Object DestinationPrefix -eq '0.0.0.0/0'|
        ForEach-Object{"$($_.InterfaceIndex)/$($_.NextHop)/$($_.RouteMetric)"}|Sort-Object)
}
function Remove-Owned {
    $saved=Import-Clixml -LiteralPath $StateFile -ErrorAction Stop
    if($saved.interfaceGuid -ne [string]$nic[0].InterfaceGuid -or $saved.count -ne $Count){
        throw 'The cluster-address snapshot does not match the owned plan.'
    }
    $owned=[Collections.Generic.HashSet[string]]::new([string[]]$plan)
    $rows=@(Get-NetIPAddress -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|
        Where-Object{(Address-Number $_.IPAddress) -ge $prefixFirst -and (Address-Number $_.IPAddress) -le $prefixLast})
    foreach($row in $rows){
        if(-not $owned.Contains($row.IPAddress) -or $row.InterfaceIndex -ne $nic[0].ifIndex -or
            $row.PrefixLength -ne 32 -or -not $row.SkipAsSource){throw 'A cluster-prefix address is not owned; refusing removal.'}
    }
    $failures=[Collections.Generic.List[Exception]]::new()
    foreach($row in $rows){
        try{Remove-NetIPAddress -InterfaceIndex $nic[0].ifIndex -IPAddress $row.IPAddress -PolicyStore ActiveStore -Confirm:$false -ErrorAction Stop}
        catch{$failures.Add($_.Exception)}
    }
    if($failures.Count){throw [AggregateException]::new('Cluster-address removal failed.',$failures)}
    if(@(Get-NetIPAddress -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|
        Where-Object{(Address-Number $_.IPAddress) -ge $prefixFirst -and (Address-Number $_.IPAddress) -le $prefixLast}).Count -or
        (@(Read-OtherAddressKeys) -join '|') -ne (@($saved.otherAddressKeys) -join '|') -or
        (@(Read-DefaultKeys) -join '|') -ne (@($saved.defaultKeys) -join '|')){
        throw 'Original addressing or default routes did not verify after cluster cleanup.'
    }
    $rows.Count
}
if($Action -eq 'remove'){
    $removed=Remove-Owned
    @{schema=1;removed=$true;removedAddresses=$removed}|ConvertTo-Json|Set-Content -LiteralPath $ReportFile
    return
}
if(Test-Path -LiteralPath $StateFile){throw 'A fresh cluster-address snapshot is required.'}
foreach($route in @(Get-NetRoute -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop)){
    if(Test-PrefixOverlap $route.DestinationPrefix){throw 'An existing route overlaps the owned cluster prefix.'}
}
if(@(Get-NetIPAddress -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|
    Where-Object{(Address-Number $_.IPAddress) -ge $prefixFirst -and (Address-Number $_.IPAddress) -le $prefixLast}).Count){
    throw 'The owned cluster prefix is already in use.'
}
@{interfaceGuid=[string]$nic[0].InterfaceGuid;count=$Count;otherAddressKeys=@(Read-OtherAddressKeys);defaultKeys=@(Read-DefaultKeys)}|
    Export-Clixml -LiteralPath $StateFile -NoClobber
$clock=[Diagnostics.Stopwatch]::StartNew()
try{
    foreach($address in $plan){
        if($clock.Elapsed.TotalSeconds -gt 600){throw 'Cluster-address preparation exceeded its deadline.'}
        $null=New-NetIPAddress -InterfaceIndex $nic[0].ifIndex -IPAddress $address -PrefixLength 32 `
            -SkipAsSource $true -PolicyStore ActiveStore -ErrorAction Stop
    }
    do{
        $rows=@(Get-NetIPAddress -InterfaceIndex $nic[0].ifIndex -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|
            Where-Object{(Address-Number $_.IPAddress) -ge $prefixFirst -and (Address-Number $_.IPAddress) -le $prefixLast})
        if(@($rows|Where-Object{[string]$_.AddressState -eq 'Duplicate'}).Count){throw 'A duplicate cluster address was detected.'}
        if($rows.Count -eq $Count -and -not @($rows|Where-Object{[string]$_.AddressState -ne 'Preferred'}).Count){break}
        if($clock.Elapsed.TotalSeconds -gt 660){throw 'Cluster addresses did not become preferred.'}
        Start-Sleep -Milliseconds 250
    }while($true)
    if((@(Read-DefaultKeys) -join '|') -ne (@((Import-Clixml $StateFile).defaultKeys) -join '|')){
        throw 'Default routing changed while preparing cluster addresses.'
    }
    @{schema=1;added=$true;ownedAddressCount=$Count;prefixLength=32;skipAsSource=$true
        preparationMilliseconds=$clock.Elapsed.TotalMilliseconds}|ConvertTo-Json|Set-Content -LiteralPath $ReportFile
}catch{
    $failure=$_
    try{$null=Remove-Owned}
    catch{throw [AggregateException]::new('Cluster-address preparation and rollback both failed.',[Exception[]]@($failure.Exception,$_.Exception))}
    throw $failure
}
