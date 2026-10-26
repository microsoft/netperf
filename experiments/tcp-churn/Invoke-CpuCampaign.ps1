# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Tools,
    [Parameter(Mandatory)][string]$Diagnostics,
    [Parameter(Mandatory)][string]$PublishDirectory,
    [Parameter(Mandatory)][string]$AnalyzerDirectory,
    [ValidateRange(15,120)][int]$Seconds=30,
    [ValidateRange(1,1024)][int]$Connections=256
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'TcpChurn.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'adapters\WindowsCts.psm1') -Force
$analyzer=Join-Path $AnalyzerDirectory 'CpuSamples.exe'
if (-not (Test-Path -LiteralPath $analyzer -PathType Leaf)) { throw 'Source-built analyzer missing.' }
$key=Get-Item -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -ErrorAction Stop
$value=$key.GetValue('EnablePMTUBHDetect',$null)
$provider=Get-WinEvent -ListProvider 'Microsoft-Windows-TCPIP' -ErrorAction Stop
$manifestEvents=@($provider.Events | ForEach-Object {
    $task=if($null -eq $_.Task){''}else{$_.Task.Name}
    if ($task -match '(?i)black|bhdetect|pmtu' -or $_.Description -match '(?i)black.?hole|full.?size.+ack') {
        [ordered]@{Id=$_.Id;Version=$_.Version;Task=$task;Description=$_.Description}
    }
})
[ordered]@{
    schema=1;bhRegistryOverridePresent=($null -ne $value);bhRegistryOverride=$value
    registryDefaultInference='not-inferred';publicProviderEvents=$manifestEvents
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $PublishDirectory 'tcp-state.json')
$owned=$false; $failure=$null
$trace=Join-Path $Diagnostics 'cpu.etl'
$timing=[ordered]@{}
$progress=[ordered]@{schema=1;stage='wpr-start';completedBatches=0;connections=0L;failureType=$null;failureCode=0;failureReason='none';traceBytes=0L;profileStopped=$false}
$totals=[ordered]@{ schema=1;workload='tcp-churn';outcome='collected';connections=0L;seconds=0.0;bytesSent=0L
    connectionsPerSecond=0.0;megabitsPerSecond=0.0;adapterTransmitDelta=0L;adapterReceiveDelta=0L
    cpuCoverage='not-measured';targetBranchCoverage='not-measured';mechanismVerified=$false;conclusion='collection-only' }
try {
    # Never cancel a pre-existing WPR session to take ownership.
    $null=Invoke-TcpChurnTool -Program "$env:SystemRoot\System32\wpr.exe" -Arguments @('-start','CPU','-filemode') `
        -Directory $Diagnostics -LogPrefix (Join-Path $Diagnostics 'wpr-start') -TimeoutSeconds 30
    $owned=$true
    $progress.stage='idle'
    $timing.idleStart=[DateTime]::UtcNow.ToString('o')
    Start-Sleep -Seconds 5
    $timing.idleEnd=[DateTime]::UtcNow.ToString('o')
    $timing.loadStart=[DateTime]::UtcNow.ToString('o')
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $progress.stage='traffic'
    $batch=0
    do {
        $directory=Join-Path $Diagnostics "batch-$batch"
        New-Item -ItemType Directory -Path $directory -ErrorAction Stop | Out-Null
        $plan=New-TcpChurnPlan -ClientAddress 192.168.1.11 -ServerAddress 192.168.1.12 `
            -Port (53617+$batch) -Connections $Connections -Seconds 15
        # Public documented socket option. No TCP global or registry setting is changed.
        $plan.ClientArguments += '-PortScalability:on'
        $adapter=New-WindowsCtsAdapter -Executable (Join-Path $Tools 'ctsTraffic.exe') `
            -DiagnosticsDirectory $directory -ClientInterface duo1 -ServerInterface duo2
        $result=Invoke-TcpChurnExperiment -Plan $plan -Adapter $adapter
        foreach ($field in @('connections','bytesSent','adapterTransmitDelta','adapterReceiveDelta')) {
            $totals[$field]+=$result.$field
        }
        $batch++
        $progress.completedBatches=$batch
        $progress.connections=$totals.connections
    } while ($clock.Elapsed.TotalSeconds -lt $Seconds -and $batch -lt 200)
    $timing.loadEnd=[DateTime]::UtcNow.ToString('o')
    $totals.seconds=$clock.Elapsed.TotalSeconds
    $totals.connectionsPerSecond=$totals.connections/$totals.seconds
    $totals.megabitsPerSecond=8.0*$totals.bytesSent/1000000.0/$totals.seconds
} catch {
    $failure=$_
    $progress.failureType=$_.Exception.GetType().FullName
    $progress.failureCode=$_.Exception.HResult
    foreach ($reason in @('Traffic command failed; diagnostics belong to the adapter.',
        'Healthy churn did not complete error-free traffic.',
        'Data was not accounted for on the selected adapters.',
        'CTS client deadline exceeded.','CTS server exited while traffic was active.')) {
        if ($_.Exception.Message -eq $reason) { $progress.failureReason=$reason }
    }
    $timing.loadEnd=[DateTime]::UtcNow.ToString('o')
}
finally {
    if ($owned) {
        try {
            $null=Invoke-TcpChurnTool -Program "$env:SystemRoot\System32\wpr.exe" -Arguments @('-stop',$trace) `
                -Directory $Diagnostics -LogPrefix (Join-Path $Diagnostics 'wpr-stop') -TimeoutSeconds 120
            $progress.profileStopped=$true
            $progress.traceBytes=(Get-Item -LiteralPath $trace).Length
        } catch {
            if ($null -ne $failure) { throw [AggregateException]::new('Campaign and owned WPR stop failed.',[Exception[]]@($failure.Exception,$_.Exception)) }
            throw
        }
        $progress | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PublishDirectory 'cpu-progress.json')
    }
}
$timing | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Diagnostics 'intervals.json')
if (-not $owned -or -not $progress.profileStopped) { throw $failure }
foreach ($interval in @('idle','load')) {
    $progress.stage="analyze-$interval"
    $progress | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PublishDirectory 'cpu-progress.json')
    $null=Invoke-TcpChurnTool -Program $analyzer -Arguments @(
        $trace,(Join-Path $PublishDirectory "cpu-$interval.json"),$timing["${interval}Start"],$timing["${interval}End"]
    ) -Directory $Diagnostics -LogPrefix (Join-Path $Diagnostics "analysis-$interval") -TimeoutSeconds 300
}
$progress.stage='complete'
$progress | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PublishDirectory 'cpu-progress.json')
if ($null -ne $failure) { throw $failure }
Export-TcpChurnPublicResult -Result ([pscustomobject]$totals) -Path (Join-Path $PublishDirectory 'result.json')
