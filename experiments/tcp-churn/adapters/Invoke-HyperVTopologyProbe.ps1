# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PublishDirectory,
    [Parameter(Mandatory)][string]$ReferenceVmName,
    [ValidateRange(1,240)][int]$ProcessorCount=128
)
$ErrorActionPreference='Stop'
if (Test-Path -LiteralPath $PublishDirectory) { throw 'Use a new publication directory.' }
$null=New-Item -ItemType Directory -Path $PublishDirectory -ErrorAction Stop
$result=[ordered]@{
    schema=1;requestedVirtualProcessors=$ProcessorCount;startupMemoryBytes=2GB;hostLogicalProcessors=0;hostPhysicalCores=0
    referenceGuestVirtualProcessors=0;configuredVirtualProcessors=0;configuredThreadsPerCore=0
    configured=$false;started=$false;cleanupVerified=$false;phase='host-query'
    failureHResult=0;processorCapacityErrorReported=$false;memoryCapacityErrorReported=$false
    rssControlPathVerified=$false;performanceVerified=$false
    conclusion='virtualization-capacity-only'
}
$vm=$null;$failure=$null;$cleanupFailure=$null;$creationAttempted=$false
$ownedName='netperf-cpu-probe-'+[guid]::NewGuid().ToString('N')
try {
    $result.hostLogicalProcessors=[int](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).NumberOfLogicalProcessors
    $result.hostPhysicalCores=[int](Get-CimInstance Win32_Processor -ErrorAction Stop|Measure-Object NumberOfCores -Sum).Sum
    $result.referenceGuestVirtualProcessors=[int](Get-VMProcessor -VMName $ReferenceVmName -ErrorAction Stop).Count
    if ([long](Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).FreePhysicalMemory -lt (4GB/1KB)) {
        throw 'Insufficient free host memory for an isolated capacity probe.'
    }
    $result.phase='create'
    $creationAttempted=$true
    $vm=New-VM -Name $ownedName `
        -Generation 2 -NoVHD -MemoryStartupBytes 2GB -ErrorAction Stop
    Set-VM -VM $vm -AutomaticStartAction Nothing -AutomaticStopAction TurnOff -CheckpointType Disabled -ErrorAction Stop
    $result.phase='configure'
    Set-VMProcessor -VM $vm -Count $ProcessorCount -HwThreadCountPerCore 1 -ErrorAction Stop
    $processor=Get-VMProcessor -VM $vm -ErrorAction Stop
    $result.configuredVirtualProcessors=[int]$processor.Count
    $result.configuredThreadsPerCore=[int]$processor.HwThreadCountPerCore
    if($result.configuredVirtualProcessors -ne $ProcessorCount -or $result.configuredThreadsPerCore -ne 1) {
        throw 'Probe topology does not match the requested single-threaded virtual cores.'
    }
    $result.configured=$true
    $result.phase='start'
    $null=Start-VM -VM $vm -ErrorAction Stop
    $running=Get-VM -Id $vm.Id -ErrorAction Stop
    if([string]$running.State -ne 'Running') { throw 'Probe did not reach running state.' }
    $result.started=$true
    $result.phase='complete'
} catch {
    $failure=$_
    $result.failureHResult=[int]$_.Exception.HResult
    $details=@($_.Exception.ToString(),$_.ErrorDetails.Message,$_.ToString()) -join "`n"
    $result.processorCapacityErrorReported=($details -match '(?is)logical processors' -and
        $details -match '(?i)not have enough|insufficient|exceed|maximum|greater|more than|limit')
    $result.memoryCapacityErrorReported=($details -match '(?is)memory' -and
        $details -match '(?i)not enough|insufficient|not available|allocate')
    $failure|Out-String|Set-Content -LiteralPath ($PublishDirectory+'.diagnostic.txt') -Encoding utf8
} finally {
    if($creationAttempted -and $null -eq $vm) {
        try {
            $matches=@(Get-VM -ErrorAction Stop|Where-Object Name -eq $ownedName)
            if($matches.Count -gt 1) { throw 'Probe identity is not unique.' }
            if($matches.Count -eq 1) { $vm=$matches[0] }
        } catch { $cleanupFailure=$_ }
    }
    if($null -ne $vm) {
        try {
            $owned=Get-VM -Id $vm.Id -ErrorAction Stop
            if([string]$owned.State -ne 'Off') { Stop-VM -VM $owned -TurnOff -Force -Confirm:$false -ErrorAction Stop }
            Remove-VM -VM $owned -Force -Confirm:$false -ErrorAction Stop
            if(@(Get-VM -ErrorAction Stop|Where-Object Id -eq $vm.Id).Count) { throw 'Owned probe VM remains registered.' }
            $result.cleanupVerified=$true
        } catch { $cleanupFailure=$_ }
    } elseif($null -eq $cleanupFailure) { $result.cleanupVerified=$true }
    $result|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $PublishDirectory 'topology-check.json') -Encoding utf8
}
if($null -ne $cleanupFailure) { throw 'Temporary topology VM cleanup failed.' }
if($null -ne $failure) {
    if($result.phase -in @('configure','start')) {
        Write-Output 'The requested topology was rejected; numeric capacity evidence was published and the owned VM removed.'
    } else { throw 'Topology probe failed before processor capacity could be tested.' }
} else { Write-Output 'The temporary diskless VM started with the requested topology and was removed; no RSS claim is made.' }
