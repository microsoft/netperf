# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 5.1
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'RssControl.psm1') -Force
function New-Settings {
    $processors=@(0..127|ForEach-Object{
        [pscustomobject]@{ProcessorGroup=[int][Math]::Floor($_/64);ProcessorNumber=$_%64;PreferenceIndex=0}
    })
    [pscustomobject]@{Name='owned-test';Enabled=$true;NumberOfReceiveQueues=128;MaxProcessors=128
        RssProcessorArraySize=128;RssProcessorArray=$processors
        IndirectionTableEntryCount=128;IndirectionTable=@($processors|ForEach-Object{
            [pscustomobject]@{Group=$_.ProcessorGroup;Number=$_.ProcessorNumber}
        })}
}
function Reject($Settings) {
    $rejected=$false
    try { $null=Assert-RssControlPath -Settings $Settings } catch { $rejected=$true }
    if(-not $rejected) { throw 'Invalid RSS state passed validation.' }
}
$checks=0
$s=New-Settings;$r=Assert-RssControlPath -Settings $s
if(-not $r.controlPathVerified -or $r.distinctAssignedProcessors -ne 128 -or
    ($r.processorGroups -join ',') -ne '0,1' -or $r.runtimeDpcCoverageVerified -or $r.performanceVerified) { throw '128-processor topology was not classified correctly.' }
$checks++
foreach($count in 1..128) {
    $s=New-Settings
    $s.MaxProcessors=$count;$s.NumberOfReceiveQueues=$count;$s.RssProcessorArraySize=$count
    $s.RssProcessorArray=@($s.RssProcessorArray|Select-Object -First $count)
    $s.IndirectionTable=@(0..127|ForEach-Object{
        [pscustomobject]@{Group=[int][Math]::Floor(($_%$count)/64);Number=($_%$count)%64}
    })
    $r=Assert-RssControlPath -Settings $s -ExpectedProcessors $count -ExpectedQueues $count
    if($r.rssProcessors -ne $count -or $r.receiveQueues -ne $count -or $r.distinctAssignedProcessors -ne $count) {
        throw "RSS count $count was rejected or rounded."
    }
    $checks++
}
foreach($count in @(0,129)) {
    foreach($parameter in @('ExpectedProcessors','ExpectedQueues')) {
        $arguments=@{Settings=(New-Settings)};$arguments[$parameter]=$count;$rejected=$false
        try { $null=Assert-RssControlPath @arguments } catch { $rejected=$true }
        if(-not $rejected) { throw "Out-of-range $parameter was accepted." }
        $checks++
    }
}
$s=New-Settings
$s.MaxProcessors=40;$s.NumberOfReceiveQueues=40;$s.RssProcessorArraySize=40
$s.RssProcessorArray=@($s.RssProcessorArray|Select-Object -First 40)
$s.IndirectionTable=@(0..127|ForEach-Object{[pscustomobject]@{Group=0;Number=$_%40}})
$r=Assert-RssControlPath -Settings $s -ExpectedProcessors 40 -ExpectedQueues 40
if($r.rssProcessors -ne 40 -or $r.receiveQueues -ne 40 -or $r.distinctAssignedProcessors -ne 40) {
    throw 'Non-power-of-two queue/processor count 40 was rejected or rounded.'
}
$checks++
$s=New-Settings
$s.RssProcessorArray=@(0..127|ForEach-Object{"$([int][Math]::Floor($_/64)):$($_%64)/0"})
$s.IndirectionTable=@(0..127|ForEach-Object{"$([int][Math]::Floor($_/64)):$($_%64)"})
$null=Assert-RssControlPath -Settings $s;$checks++
$s=New-Settings
$s.MaxProcessors=80;$s.RssProcessorArraySize=80;$s.RssProcessorArray=@($s.RssProcessorArray|Select-Object -First 80)
$s.IndirectionTable=@(0..127|ForEach-Object{
    [pscustomobject]@{Group=[int][Math]::Floor(($_%80)/64);Number=($_%80)%64}
})
$r=Assert-RssControlPath -Settings $s -ExpectedProcessors 80
if($r.distinctAssignedProcessors -ne 80) { throw 'A non-power-of-two processor count was rejected or miscounted.' }
$checks++
foreach($mutate in @(
    {$args[0].Enabled=$false},
    {$args[0].NumberOfReceiveQueues=16},
    {$args[0].MaxProcessors=16},
    {$args[0].RssProcessorArraySize=127},
    {$args[0].IndirectionTableEntryCount=127},
    {$args[0].RssProcessorArray[127]=$args[0].RssProcessorArray[0]},
    {$args[0].IndirectionTable[127]=$args[0].IndirectionTable[0]},
    {$args[0].IndirectionTable[127]=[pscustomobject]@{Group=2;Number=0}},
    {$args[0].RssProcessorArray[127]=[pscustomobject]@{ProcessorGroup=0;ProcessorNumber=127}},
    {$args[0].RssProcessorArray[0]=[pscustomobject]@{ProcessorGroup=$null;ProcessorNumber=0}},
    {$args[0].RssProcessorArray[0]=[pscustomobject]@{ProcessorGroup=0.5;ProcessorNumber=0}},
    {$args[0].IndirectionTable[127]='0:128'},
    {$args[0].IndirectionTable[127]='unrecognized'},
    {$args[0].IndirectionTable[127]=$null}
)) { $s=New-Settings;& $mutate $s;Reject $s;$checks++ }
function Get-NetAdapterRss {
    param($Name,$ErrorAction)
    $global:TcpChurnRssTest.Reads++
    if($global:TcpChurnRssTest.Case -eq 'read-error') { throw 'Simulated CIM failure.' }
    if($global:TcpChurnRssTest.Case -eq 'changed' -and $global:TcpChurnRssTest.Reads -eq 2) {
        $global:TcpChurnRssTest.Settings.IndirectionTable[127]=$global:TcpChurnRssTest.Settings.IndirectionTable[0]
    }
    $global:TcpChurnRssTest.Settings
}
function Start-Sleep { param($Seconds) }
foreach($case in @('valid','changed','wrong-adapter','read-error')) {
    $global:TcpChurnRssTest=@{Case=$case;Settings=(New-Settings);Reads=0}
    if($case -eq 'wrong-adapter') { $global:TcpChurnRssTest.Settings.Name='not-the-requested-adapter' }
    $path=Join-Path ([IO.Path]::GetTempPath()) ('rss-control-test-'+[guid]::NewGuid().ToString('N')+'.json')
    try {
        $failed=$false
        try { & (Join-Path $PSScriptRoot 'Invoke-RssControlCheck.ps1') -AdapterName 'owned-test' -PublishFile $path }
        catch { $failed=$true }
        $result=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
        if($failed -ne ($case -ne 'valid') -or $result.controlPathVerified -ne ($case -eq 'valid') -or $result.adapterConfigurationChanged) {
            throw "Incorrect read-only wrapper outcome for $case."
        }
        if($case -in @('valid','changed') -and $global:TcpChurnRssTest.Reads -ne 2) { throw 'RSS state was not re-read.' }
        $checks++
    } finally {
        if(Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -ErrorAction Stop }
        Remove-Variable -Name TcpChurnRssTest -Scope Global
    }
}
Write-Output "Passed $checks RSS control-path cases; simulated data is not runtime coverage."
