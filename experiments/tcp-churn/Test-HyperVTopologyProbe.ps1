# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
$ErrorActionPreference='Stop'
$global:TcpChurnTopologyMock=$null
function Get-CimInstance {
    param($ClassName,$ErrorAction)
    switch($ClassName) {
        Win32_ComputerSystem { [pscustomobject]@{NumberOfLogicalProcessors=80} }
        Win32_Processor { [pscustomobject]@{NumberOfCores=40} }
        Win32_OperatingSystem { [pscustomobject]@{FreePhysicalMemory=8GB/1KB} }
        default { throw 'Unexpected CIM query.' }
    }
}
function Get-VMProcessor {
    param($VMName,$VM,$ErrorAction)
    if($VMName) { [pscustomobject]@{Count=80} }
    else { [pscustomobject]@{Count=$global:TcpChurnTopologyMock.Count;HwThreadCountPerCore=1} }
}
function New-VM {
    param($Name,$Generation,[switch]$NoVHD,$MemoryStartupBytes,$ErrorAction)
    if($Generation -ne 2 -or -not $NoVHD -or $MemoryStartupBytes -ne 2GB) { throw 'Unsafe probe creation.' }
    $global:TcpChurnTopologyMock.VM=[pscustomobject]@{Id=[guid]::NewGuid();Name=$Name;State='Off'}
    $global:TcpChurnTopologyMock.Registered=$true
    if($global:TcpChurnTopologyMock.Phase -eq 'partial-create') { throw 'Simulated partial create failure.' }
    $global:TcpChurnTopologyMock.VM
}
function Set-VM { param($VM,$AutomaticStartAction,$AutomaticStopAction,$CheckpointType,$ErrorAction) }
function Set-VMProcessor {
    param($VM,$Count,$HwThreadCountPerCore,$ErrorAction)
    if($global:TcpChurnTopologyMock.Phase -eq 'configure') { throw 'Simulated CPU rejection.' }
    if($HwThreadCountPerCore -ne 1) { throw 'Virtual SMT was not disabled.' }
    $global:TcpChurnTopologyMock.Count=$Count
}
function Start-VM {
    param($VM,$ErrorAction)
    if($global:TcpChurnTopologyMock.Phase -eq 'start') { throw 'Simulated start rejection.' }
    $global:TcpChurnTopologyMock.VM.State='Running'
}
function Get-VM {
    param($Id,$ErrorAction)
    if($global:TcpChurnTopologyMock.Registered) { $global:TcpChurnTopologyMock.VM }
    if(-not $Id) { [pscustomobject]@{Id=[guid]::Empty;Name='unrelated-existing-guest';State='Running'} }
}
function Stop-VM {
    [CmdletBinding(SupportsShouldProcess)]
    param($VM,[switch]$TurnOff,[switch]$Force)
    if($VM.Id -ne $global:TcpChurnTopologyMock.VM.Id -or -not $TurnOff -or -not $Force) { throw 'Unsafe stop.' }
    $global:TcpChurnTopologyMock.Stops++
    $global:TcpChurnTopologyMock.VM.State='Off'
}
function Remove-VM {
    [CmdletBinding(SupportsShouldProcess)]
    param($VM,[switch]$Force)
    if($global:TcpChurnTopologyMock.Phase -eq 'cleanup') { throw 'Simulated cleanup failure.' }
    if($VM.Id -ne $global:TcpChurnTopologyMock.VM.Id -or -not $Force) { throw 'Unsafe removal.' }
    $global:TcpChurnTopologyMock.Registered=$false
}
$checks=0
foreach($phase in @('success','configure','start','partial-create','cleanup')) {
    $global:TcpChurnTopologyMock=@{Phase=$phase;VM=$null;Registered=$false;Count=0;Stops=0}
    $root=Join-Path ([IO.Path]::GetTempPath()) ('topology-test-'+[guid]::NewGuid().ToString('N'))
    try {
        $failed=$false
        try { & (Join-Path $PSScriptRoot 'adapters\Invoke-HyperVTopologyProbe.ps1') -PublishDirectory $root -ReferenceVmName 'reference' | Out-Null }
        catch { $failed=$true;$reason=$_ }
        if($failed -ne ($phase -in @('partial-create','cleanup'))) {
            $diagnostic=if(Test-Path -LiteralPath ($root+'.diagnostic.txt')) { Get-Content -LiteralPath ($root+'.diagnostic.txt') -Raw } else { [string]$reason }
            throw "Unexpected outcome for ${phase}: $diagnostic"
        }
        $result=Get-Content -LiteralPath (Join-Path $root 'topology-check.json') -Raw|ConvertFrom-Json
        if($result.cleanupVerified -ne ($phase -ne 'cleanup')) { throw "Incorrect cleanup report for $phase." }
        if($result.started -ne ($phase -in @('success','cleanup'))) { throw "Incorrect start report for $phase." }
        if($result.rssControlPathVerified -or $result.performanceVerified) { throw 'Capacity probe claimed RSS/performance validation.' }
        if($phase -eq 'success' -and ($result.configuredVirtualProcessors -ne 128 -or $global:TcpChurnTopologyMock.Stops -ne 1)) {
            throw 'Successful probe did not exercise 128-vCPU startup and owned shutdown.'
        }
        Remove-Variable -Name TcpChurnTopologyMock -Scope Global
        $checks++
    } finally {
        foreach($path in @((Join-Path $root 'topology-check.json'),($root+'.diagnostic.txt'))) {
            if(Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -ErrorAction Stop }
        }
        if(Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -ErrorAction Stop }
    }
}
Write-Output "Passed $checks mocked Hyper-V lifecycle cases; no real VM operations."
