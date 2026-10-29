# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('add','remove')][string]$Action,
    [Parameter(Mandatory)][string]$InterfaceAlias,
    [Parameter(Mandatory)][string]$StateFile,
    [Parameter(Mandatory)][string]$ReportFile
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$prefix='198.19.64.0/22'
# One gateway on the data interface, standing in for that interface's single default gateway.
$gateways=@(@{NextHop='198.19.240.5';Metric=10})
$nic=@(Get-NetAdapter -Name $InterfaceAlias -ErrorAction Stop)
if($nic.Count -ne 1){throw 'The owned data interface must be unique.'}
function Read-PrefixRoutes {
    @(Get-NetRoute -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|Where-Object DestinationPrefix -eq $prefix)
}
function Read-RouteKeys {
    @(Get-NetRoute -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|Where-Object DestinationPrefix -ne $prefix|
        ForEach-Object{"$($_.InterfaceIndex)/$($_.DestinationPrefix)/$($_.NextHop)/$($_.RouteMetric)"}|Sort-Object)
}
function Remove-Owned {
    $saved=Import-Clixml -LiteralPath $StateFile -ErrorAction Stop
    if($saved.interfaceGuid -ne [string]$nic[0].InterfaceGuid){throw 'The cluster-route snapshot does not match the owned interface.'}
    $rows=@(Read-PrefixRoutes)
    foreach($row in $rows){
        if($row.InterfaceIndex -ne $nic[0].ifIndex -or $row.NextHop -notin $gateways.NextHop){
            throw 'A cluster-prefix route is not owned; refusing removal.'
        }
    }
    $failures=[Collections.Generic.List[Exception]]::new()
    foreach($row in $rows){
        try{Remove-NetRoute -InterfaceIndex $nic[0].ifIndex -DestinationPrefix $prefix -NextHop $row.NextHop `
            -PolicyStore ActiveStore -Confirm:$false -ErrorAction Stop}catch{$failures.Add($_.Exception)}
    }
    if($failures.Count){throw [AggregateException]::new('Cluster-route removal failed.',$failures)}
    if(@(Read-PrefixRoutes).Count -or (@(Read-RouteKeys) -join '|') -ne (@($saved.otherRouteKeys) -join '|')){
        throw 'Original routes did not verify after cluster-route cleanup.'
    }
    $rows.Count
}
if($Action -eq 'remove'){
    $removed=Remove-Owned
    @{schema=1;removed=$true;removedRoutes=$removed}|ConvertTo-Json|Set-Content -LiteralPath $ReportFile
    return
}
if(Test-Path -LiteralPath $StateFile){throw 'A fresh cluster-route snapshot is required.'}
if(@(Read-PrefixRoutes).Count){throw 'The owned cluster prefix already has routes.'}
foreach($route in @(Get-NetRoute -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop)){
    if($route.DestinationPrefix -match '^198\.19\.(6[4-7])\.' ){throw 'An existing route overlaps the owned cluster prefix.'}
}
$onLink=@(Get-NetIPAddress -InterfaceIndex $nic[0].ifIndex -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|
    Where-Object{$_.IPAddress -match '^198\.19\.240\.[1-4]$' -and $_.PrefixLength -eq 29})
if(-not $onLink.Count){throw 'Cluster gateways require the owned on-link benchmark data addresses.'}
@{interfaceGuid=[string]$nic[0].InterfaceGuid;otherRouteKeys=@(Read-RouteKeys)}|Export-Clixml -LiteralPath $StateFile -NoClobber
try{
    foreach($gateway in $gateways){
        $null=New-NetRoute -InterfaceIndex $nic[0].ifIndex -DestinationPrefix $prefix -NextHop $gateway.NextHop `
            -RouteMetric $gateway.Metric -PolicyStore ActiveStore -ErrorAction Stop
    }
    $rows=@(Read-PrefixRoutes)
    if($rows.Count -ne $gateways.Count -or @($rows|Where-Object InterfaceIndex -ne $nic[0].ifIndex).Count){
        throw 'The owned cluster gateway route did not verify.'
    }
    @{schema=1;added=$true;prefix=$prefix;gatewayRoutes=$gateways.Count;gatewayMetric=10}|
        ConvertTo-Json|Set-Content -LiteralPath $ReportFile
}catch{
    $failure=$_
    try{$null=Remove-Owned}
    catch{throw [AggregateException]::new('Cluster-route preparation and rollback both failed.',[Exception[]]@($failure.Exception,$_.Exception))}
    throw $failure
}
