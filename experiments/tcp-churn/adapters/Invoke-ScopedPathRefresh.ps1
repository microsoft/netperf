# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InterfaceAlias,
    [Parameter(Mandatory)][string]$DataStateFile,
    [Parameter(Mandatory)][string]$StateFile,
    [Parameter(Mandatory)][string]$ReportFile,
    [string]$ReadyFile,
    [string]$BeginFile,
    [string]$StopFile,
    [ValidateSet('0.0.0.0','198.19.240.5')][string]$NextHop='0.0.0.0',
    [string]$ExpectedPeerMac,
    [ValidateRange(100,180000)][int]$MaximumHoldMilliseconds=180000,
    [switch]$RestoreOnly
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if(-not $RestoreOnly -and (!$ReadyFile -or !$BeginFile -or !$StopFile)){
    throw 'The path-refresh control requires owned lifecycle files.'
}
$prefix='198.19.240.6/32'
$adapter=@(Get-NetAdapter -Name $InterfaceAlias -ErrorAction Stop)
if($adapter.Count -ne 1){throw 'The owned data adapter must be unique.'}
$data=Import-Clixml -LiteralPath $DataStateFile -ErrorAction Stop
if($data.interfaceGuid -ne [string]$adapter[0].InterfaceGuid -or -not $data.originalDhcpDisabled -or
    @($data.addresses).Count -lt 1 -or @($data.addresses|Where-Object{$_ -notmatch '^198\.19\.240\.[1-4]$'}).Count){
    throw 'The path-refresh control requires the verified owned client data fixture.'
}
function Read-Defaults {
    @(Get-NetRoute -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|
        Where-Object DestinationPrefix -eq '0.0.0.0/0'|
        ForEach-Object{"$($_.InterfaceIndex)/$($_.NextHop)/$($_.RouteMetric)"}|Sort-Object)
}
function Read-ControlRoute {
    @(Get-NetRoute -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|
        Where-Object DestinationPrefix -eq $prefix)
}
function Remove-ControlRoute {
    $saved=Import-Clixml -LiteralPath $StateFile -ErrorAction Stop
    if($saved.interfaceGuid -ne [string]$adapter[0].InterfaceGuid -or $saved.prefix -ne $prefix -or
        $saved.nextHop -ne $NextHop -or $saved.metric -ne 1 -or -not $saved.originalAbsent){
        throw 'The route snapshot does not match the owned control.'
    }
    $current=@(Read-ControlRoute)
    if($current.Count -gt 1){throw 'The owned control route is no longer unique.'}
    if($current.Count) {
        if($current[0].InterfaceIndex -ne $adapter[0].ifIndex -or $current[0].NextHop -ne $saved.nextHop -or
            $current[0].RouteMetric -ne $saved.metric){throw 'The control route changed ownership; refusing removal.'}
        Remove-NetRoute -InterfaceIndex $adapter[0].ifIndex -DestinationPrefix $prefix -NextHop $NextHop `
            -PolicyStore ActiveStore -Confirm:$false -ErrorAction Stop
    }
    if(@(Read-ControlRoute).Count -or
        (@(Read-Defaults) -join '|') -ne (@($data.originalDefaultKeys) -join '|')){
        throw 'Control-route removal or unchanged default routing did not verify.'
    }
}
if($RestoreOnly) {
    Remove-ControlRoute
    @{schema=1;removed=$true;defaultRoutesPreserved=$true}|ConvertTo-Json|Set-Content -LiteralPath $ReportFile
    return
}
if(Test-Path $StateFile){throw 'A fresh path-refresh ownership snapshot is required.'}
if(@(Read-ControlRoute).Count){throw 'An existing host route conflicts with the owned control.'}
$connected=@(Get-NetRoute -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|
    Where-Object{$_.DestinationPrefix -eq '198.19.240.0/29' -and $_.InterfaceIndex -eq $adapter[0].ifIndex -and $_.NextHop -eq '0.0.0.0'})
$network=@(Get-NetIPInterface -InterfaceIndex $adapter[0].ifIndex -AddressFamily IPv4 -ErrorAction Stop)
$addresses=@(Get-NetIPAddress -InterfaceIndex $adapter[0].ifIndex -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|
    Where-Object{$_.IPAddress -in $data.addresses -and $_.PrefixLength -eq 29 -and $_.SkipAsSource -eq $true})
if($connected.Count -ne 1 -or $network.Count -ne 1 -or [string]$network[0].Dhcp -ne 'Disabled' -or
    $addresses.Count -ne @($data.addresses).Count -or
    (@(Read-Defaults) -join '|') -ne (@($data.originalDefaultKeys) -join '|')){
    throw 'Owned data-prefix and unchanged static management policy must verify before route refresh.'
}
$peerVerified=$false
if($NextHop -ne '0.0.0.0') {
    if([string]::IsNullOrWhiteSpace($ExpectedPeerMac)){throw 'An owned logical gateway requires the verified peer MAC.'}
    $neighbor=@(Get-NetNeighbor -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|
        Where-Object IPAddress -eq $NextHop)
    if($neighbor.Count -ne 1 -or $neighbor[0].LinkLayerAddress -ne $ExpectedPeerMac){
        throw 'The logical gateway does not match the verified owned peer MAC.'
    }
    $peerVerified=$true
}
@{interfaceGuid=[string]$adapter[0].InterfaceGuid;prefix=$prefix;nextHop=$NextHop;metric=1;originalAbsent=$true}|
    Export-Clixml -LiteralPath $StateFile -NoClobber
$changed=$false;$failure=$null;$restoreFailure=$null
$report=[ordered]@{schema=1;scenario='equivalent-owned-host-route-control';added=$false;removed=$false
    sameInterfaceAndNextHop=($NextHop -eq '0.0.0.0');sameInterface=$true;peerMacVerified=$peerVerified
    nextHopKind=$(if($NextHop -eq '0.0.0.0'){'onlink'}else{'owned-peer-gateway'})
    defaultRoutesPreserved=$false;routeAdditions=0;scope='owned-benchmark-peer-only'}
try {
    [IO.File]::WriteAllText($ReadyFile,'ready')
    $wait=[Diagnostics.Stopwatch]::StartNew()
    while(-not(Test-Path -LiteralPath $BeginFile)) {
        if(Test-Path -LiteralPath $StopFile){throw 'The workload stopped before the route-refresh control.'}
        if($wait.Elapsed.TotalSeconds -gt 60){throw 'No real-GC pre-call signal reached the bounded route control.'}
        Start-Sleep -Milliseconds 25
    }
    if(Test-Path -LiteralPath $StopFile){throw 'The workload stopped before the owned route addition.'}
    $report.applyStartUtc=[DateTime]::UtcNow.ToString('o')
    $changed=$true
    $null=New-NetRoute -InterfaceIndex $adapter[0].ifIndex -DestinationPrefix $prefix -NextHop $NextHop `
        -RouteMetric 1 -PolicyStore ActiveStore -ErrorAction Stop
    $report.applyEndUtc=[DateTime]::UtcNow.ToString('o')
    $current=@(Read-ControlRoute)
    if($current.Count -ne 1 -or $current[0].InterfaceIndex -ne $adapter[0].ifIndex -or
        $current[0].NextHop -ne $NextHop -or $current[0].RouteMetric -ne 1){throw 'The owned route addition did not verify.'}
    $report.added=$true;$report.routeAdditions=1;$report.addedUtc=[DateTime]::UtcNow.ToString('o')
    $hold=[Diagnostics.Stopwatch]::StartNew()
    while(-not(Test-Path -LiteralPath $StopFile) -and $hold.Elapsed.TotalMilliseconds -lt $MaximumHoldMilliseconds){
        Start-Sleep -Milliseconds 50
    }
    $report.activeMilliseconds=$hold.Elapsed.TotalMilliseconds
}catch{$failure=$_}
finally {
    try {
        if($changed){Remove-ControlRoute}
        elseif(@(Read-ControlRoute).Count -or
            (@(Read-Defaults) -join '|') -ne (@($data.originalDefaultKeys) -join '|')){
            throw 'Routing changed before the owned control; no unowned route was removed.'
        }
        $report.removed=$true;$report.defaultRoutesPreserved=$true;$report.removedUtc=[DateTime]::UtcNow.ToString('o')
    }catch{$restoreFailure=$_}
    $report.outcome=if($null -eq $failure -and $null -eq $restoreFailure){'completed'}else{'failed'}
    if($null -ne $failure){$report.failureType=$failure.Exception.GetType().FullName}
    if($null -ne $restoreFailure){$report.restoreFailureType=$restoreFailure.Exception.GetType().FullName}
    $report|ConvertTo-Json|Set-Content -LiteralPath $ReportFile
}
if($null -ne $failure -or $null -ne $restoreFailure){
    $errors=[Collections.Generic.List[Exception]]::new()
    if($null -ne $failure){$errors.Add($failure.Exception)}
    if($null -ne $restoreFailure){$errors.Add($restoreFailure.Exception)}
    throw [AggregateException]::new('The owned route-refresh control or restoration failed.',$errors)
}
