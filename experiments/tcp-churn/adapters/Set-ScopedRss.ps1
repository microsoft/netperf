# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('prepare','restore')][string]$Action,
    [Parameter(Mandatory)][string]$StateFile,
    [Parameter(Mandatory)][string]$ReportFile,
    [string]$InterfaceAlias,
    [ValidateRange(1,128)][int]$Processors=64
)
$ErrorActionPreference='Stop'
function Read-Addresses($Adapter) {
    @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop|
        Where-Object InterfaceIndex -eq $Adapter.ifIndex|
        ForEach-Object{"$($_.InterfaceIndex)/$($_.IPAddress)/$($_.PrefixLength)/$($_.SkipAsSource)"}|Sort-Object)
}
function Read-Defaults {
    @(Get-NetRoute -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|
        Where-Object DestinationPrefix -eq '0.0.0.0/0'|
        ForEach-Object{"$($_.InterfaceIndex)/$($_.NextHop)/$($_.RouteMetric)"}|Sort-Object)
}
function Apply-Rss($Adapter,$Settings) {
    $null=Set-NetAdapterRss -Name $Adapter.Name -Enabled $Settings.Enabled -Profile $Settings.Profile `
        -NumberOfReceiveQueues $Settings.Queues -MaxProcessors $Settings.MaxProcessors `
        -BaseProcessorGroup $Settings.BaseGroup -BaseProcessorNumber $Settings.BaseNumber `
        -MaxProcessorGroup $Settings.MaxGroup -MaxProcessorNumber $Settings.MaxNumber -NoRestart -ErrorAction Stop
}
function Read-Settings($Rss) {
    @{Enabled=[bool]$Rss.Enabled;Profile=[string]$Rss.Profile;Queues=[int]$Rss.NumberOfReceiveQueues
        MaxProcessors=[int]$Rss.MaxProcessors;BaseGroup=[int]$Rss.BaseProcessorGroup;BaseNumber=[int]$Rss.BaseProcessorNumber
        MaxGroup=[int]$Rss.MaxProcessorGroup;MaxNumber=[int]$Rss.MaxProcessorNumber}
}
function Read-ProcessorRange([int]$Count) {
    if(-not ('NetperfRssNative' -as [type])){
        Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class NetperfRssNative {
    [DllImport("kernel32.dll")] public static extern ushort GetActiveProcessorGroupCount();
    [DllImport("kernel32.dll")] public static extern uint GetActiveProcessorCount(ushort group);
}
'@
    }
    $remaining=$Count
    for($group=0;$group -lt [NetperfRssNative]::GetActiveProcessorGroupCount();$group++){
        $active=[int][NetperfRssNative]::GetActiveProcessorCount($group)
        if($remaining -le $active){return @{Group=$group;Number=$remaining-1}}
        $remaining-=$active
    }
    throw 'The requested RSS range exceeds the active processor groups.'
}
if($Action -eq 'prepare'){
    if(Test-Path -LiteralPath $StateFile){throw 'Use a fresh owned RSS snapshot.'}
    if([string]::IsNullOrWhiteSpace($InterfaceAlias)){throw 'The RSS control requires the verified peer-route interface.'}
    $adapters=@(Get-NetAdapter -Name $InterfaceAlias -ErrorAction Stop)
    if($adapters.Count -ne 1){throw 'The RSS control adapter is not unique.'}
    $adapter=$adapters[0]
    $rss=@(Get-NetAdapterRss -Name $adapter.Name -ErrorAction Stop)
    if($rss.Count -ne 1 -or -not $rss[0].Enabled){throw 'The RSS control requires an already-enabled supported adapter.'}
    $logical=(Get-CimInstance Win32_Processor|Measure-Object NumberOfLogicalProcessors -Sum).Sum
    if($Processors -gt $logical){throw 'The requested RSS processors exceed the guest CPU inventory.'}
    $saved=@{owner='tcp-churn-rss-v1';interfaceGuid=[string]$adapter.InterfaceGuid;alias=$adapter.Name
        settings=(Read-Settings $rss[0]);activeArrayCount=@($rss[0].RssProcessorArray).Count
        addresses=@(Read-Addresses $adapter);defaults=@(Read-Defaults)}
    $saved|Export-Clixml -LiteralPath $StateFile -NoClobber
    $range=Read-ProcessorRange $Processors
    $target=@{Enabled=$true;Profile=$saved.settings.Profile;Queues=$Processors;MaxProcessors=$Processors
        BaseGroup=0;BaseNumber=0;MaxGroup=$range.Group;MaxNumber=$range.Number}
}else{
    $saved=Import-Clixml -LiteralPath $StateFile -ErrorAction Stop
    if($saved.owner -ne 'tcp-churn-rss-v1'){throw 'The RSS snapshot is not owned by this control.'}
    $adapters=@(Get-NetAdapter -Name $saved.alias -ErrorAction Stop)
    if($adapters.Count -ne 1 -or [string]$adapters[0].InterfaceGuid -ne $saved.interfaceGuid){
        throw 'The RSS adapter identity changed; refusing mutation.'
    }
    $adapter=$adapters[0];$target=$saved.settings
}
Apply-Rss $adapter $target
$actual=@(Get-NetAdapterRss -Name $adapter.Name -ErrorAction Stop)
if($actual.Count -ne 1){throw 'The applied RSS configuration is not unique.'}
$settings=Read-Settings $actual[0]
foreach($key in $target.Keys){
    if([string]$settings[$key] -ne [string]$target[$key]){throw 'The requested no-restart RSS configuration did not read back exactly.'}
}
if($Action -eq 'prepare' -and @($actual[0].RssProcessorArray).Count -lt $Processors){
    throw 'The active RSS processor array did not reach the requested count; no adapter restart will be attempted.'
}
if($Action -eq 'restore' -and @($actual[0].RssProcessorArray).Count -ne $saved.activeArrayCount){
    throw 'The original active RSS processor array did not restore exactly.'
}
if((@(Read-Addresses $adapter)-join '|') -ne (@($saved.addresses)-join '|') -or
    (@(Read-Defaults)-join '|') -ne (@($saved.defaults)-join '|')){
    throw 'RSS setup/restoration changed original IPv4 addresses or default routes.'
}
@{schema=1;action=$Action;verified=$true;adapterRestarted=$false
    queues=$settings.Queues;maxProcessors=$settings.MaxProcessors
    activeProcessorArrayCount=@($actual[0].RssProcessorArray).Count
    originalQueues=$saved.settings.Queues;originalMaxProcessors=$saved.settings.MaxProcessors
    originalAddressesAndDefaultsPreserved=$true}|ConvertTo-Json|Set-Content -LiteralPath $ReportFile
