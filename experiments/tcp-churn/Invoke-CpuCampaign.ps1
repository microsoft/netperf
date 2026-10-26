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
    [ValidateRange(1,1024)][int]$Connections=256,
    [switch]$SynDrop,
    $PeerSession,
    [string]$PeerRoot,
    [string]$ClientInterface='duo1',
    [string]$PeerInterface='duo2',
    [string]$FixedClientAddress,
    [string]$PeerAddress='192.168.1.12'
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
$keywords=0L
$manifestEvents=@($provider.Events | ForEach-Object {
    $task=if($null -eq $_.Task){''}else{$_.Task.Name}
    if ($task -match '(?i)black|bhdetect|pmtu' -or $_.Description -match '(?i)black.?hole|full.?size.+ack' -or
        $task -in @('TcpTcbSynSend','TcpDisconnectTcbRtoTimeout','TcpDataTransferRetransmitRound')) {
        foreach ($keyword in $_.Keywords) { $keywords=$keywords -bor $keyword.Value }
        [ordered]@{Id=$_.Id;Version=$_.Version;Task=$task;Description=$_.Description}
    }
})
[ordered]@{
    schema=1;bhRegistryOverridePresent=($null -ne $value);bhRegistryOverride=$value
    registryDefaultInference='not-inferred';publicProviderEvents=$manifestEvents
    publicProviderGuid=[string]$provider.Id;publicProbeKeywordMask=$keywords.ToString('X16')
    fixtureRss=@(foreach($alias in @($ClientInterface)) {
        Get-NetAdapterRss -Name $alias -ErrorAction Stop |
            Select-Object Enabled,NumberOfReceiveQueues,MaxProcessors,BaseProcessorGroup,BaseProcessorNumber,MaxProcessorGroup,MaxProcessorNumber
    })
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $PublishDirectory 'tcp-state.json')
$owned=$false; $failure=$null
$eventOwned=$false
$collector=$null
$ready=Join-Path $Diagnostics 'probe-ready'
$stop=Join-Path $Diagnostics 'probe-stop'
$eventTrace=Join-Path $Diagnostics 'tcp-probes.etl'
$blockRule='TcpChurnSynDrop-'+[guid]::NewGuid().ToString('N')
$blockOwned=$false
$trace=Join-Path $Diagnostics 'cpu.etl'
$timing=[ordered]@{}
$progress=[ordered]@{schema=1;stage='wpr-start';completedBatches=0;connections=0L;failureType=$null;failureCode=0;toolExitCode=0;failureReason='none';traceBytes=0L;profileStopped=$false}
$totals=[ordered]@{ schema=1;workload='tcp-churn';outcome='collected';connections=0L;seconds=0.0;bytesSent=0L
    connectionsPerSecond=0.0;megabitsPerSecond=0.0;adapterTransmitDelta=0L;adapterReceiveDelta=0L
    cpuCoverage='not-measured';targetBranchCoverage='not-measured';mechanismVerified=$false;conclusion='collection-only' }
try {
    # Never cancel a pre-existing WPR session to take ownership.
    $null=Invoke-TcpChurnTool -Program "$env:SystemRoot\System32\wpr.exe" -Arguments @('-start','CPU','-filemode') `
        -Directory $Diagnostics -LogPrefix (Join-Path $Diagnostics 'wpr-start') -TimeoutSeconds 30
    $owned=$true
    $progress.stage='probes-start'
    $collector=Start-TcpChurnCollector -Program $analyzer -Arguments @(
        '--capture-probes',$eventTrace,(Join-Path $PublishDirectory 'tcp-state.json'),$ready,$stop,'300'
    ) -Directory $Diagnostics -LogPrefix (Join-Path $Diagnostics 'probes')
    $eventOwned=$true
    $readiness=[Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Path -LiteralPath $ready)) {
        if ($collector.Process.HasExited -or $readiness.Elapsed.TotalSeconds -gt 20) { throw 'Exact probe collector did not become ready.' }
        Start-Sleep -Milliseconds 100
    }
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
        $source=if($FixedClientAddress){$FixedClientAddress}else{"192.168.1.$(21+($batch%8))"}
        $plan=New-TcpChurnPlan -ClientAddress $source -ServerAddress $PeerAddress `
            -Port (53617+$batch) -Connections $Connections -Seconds ([Math]::Min(120,$Seconds+30))
        # Public documented socket option. No TCP global or registry setting is changed.
        $plan.ClientArguments += '-PortScalability:on'
        if ($null -ne $PeerSession) {
            $adapter=New-RemoteWindowsCtsAdapter -Executable (Join-Path $Tools 'ctsTraffic.exe') -DiagnosticsDirectory $directory `
                -ClientInterface $ClientInterface -PeerInterface $PeerInterface -PeerSession $PeerSession -PeerRoot $PeerRoot -DropSyn ([bool]$SynDrop)
        } else {
            $adapter=New-WindowsCtsAdapter -Executable (Join-Path $Tools 'ctsTraffic.exe') `
                -DiagnosticsDirectory $directory -ClientInterface duo1 -ServerInterface duo2
        }
        if ($SynDrop) {
            $plan.ClientArguments=@($plan.ClientArguments|Where-Object{$_ -notlike '-iterations:*'})
            $plan.ClientArguments+='-iterations:1'
            if ($null -eq $PeerSession) {
                $null=New-NetFirewallRule -Name $blockRule -DisplayName $blockRule -Direction Inbound `
                    -Action Block -Protocol TCP -LocalPort $plan.Port -LocalAddress $plan.ServerAddress `
                    -RemoteAddress $plan.ClientAddress -ErrorAction Stop
                $blockOwned=$true
            }
            try {
                $null=& $adapter.StartPeer $adapter.State $plan
                if ($null -ne $PeerSession) { $progress['peerFirewall']=$adapter.State.PeerConfig|Select-Object OriginallyEnabledProfiles,TemporarilyEnabledProfiles }
                $listen=[Diagnostics.Stopwatch]::StartNew()
                while (-not (& $adapter.PeerReady $adapter.State $plan)) {
                    if ($listen.Elapsed.TotalSeconds -gt 20) { throw 'Owned SYN-drop listener did not become ready.' }
                    Start-Sleep -Milliseconds 100
                }
                $execution=& $adapter.RunClient $adapter.State $plan
                $summary=ConvertFrom-CtsChurnOutput $execution.Text
                $progress['synOutcomes']=$summary|Select-Object Completed,NetworkErrors,ProtocolErrors,Milliseconds
                if ($summary.Completed -ne 0 -or $summary.ProtocolErrors -ne 0 -or
                    $summary.NetworkErrors -ne $Connections -or $execution.ExitCode -ne $Connections -or
                    $summary.Milliseconds -lt 3000) {
                    throw 'SYN-drop outcomes do not match the deliberately blocked connection attempts.'
                }
                $totals.outcome='observed-syn-failures'
                $totals['failedConnections']=$summary.NetworkErrors
                $totals['fault']='scoped-silent-syn-drop'
            } finally { $null=& $adapter.Close $adapter.State $plan }
            break
        }
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
    if ($_.Exception.Data.Contains('ToolExitCode')) { $progress.toolExitCode=[int]$_.Exception.Data['ToolExitCode'] }
    foreach ($reason in @('Traffic command failed; diagnostics belong to the adapter.',
        'Healthy churn did not complete error-free traffic.',
        'Data was not accounted for on the selected adapters.',
        'CTS client deadline exceeded.','CTS server exited while traffic was active.')) {
        if ($_.Exception.Message -eq $reason) { $progress.failureReason=$reason }
    }
    $timing.loadEnd=[DateTime]::UtcNow.ToString('o')
}
finally {
    if ($blockOwned) {
        try { Remove-NetFirewallRule -Name $blockRule -ErrorAction Stop }
        catch { if($null -eq $failure){$failure=$_}else{Write-Warning 'Owned SYN-drop rule cleanup also failed.'} }
    }
    if ($eventOwned) {
        try {
            [IO.File]::WriteAllText($stop,'stop')
            if (-not $collector.Process.WaitForExit(20000)) { throw 'Exact probe collector did not stop.' }
            if ($collector.Process.ExitCode -ne 0) { throw 'Exact probe collector failed.' }
        } catch {
            if ($null -eq $failure) { $failure=$_ }
            else {
                $combined=[AggregateException]::new('Traffic and owned probe stop failed.',[Exception[]]@($failure.Exception,$_.Exception))
                $failure=[Management.Automation.ErrorRecord]::new($combined,'ProbeStopFailed',[Management.Automation.ErrorCategory]::CloseError,$null)
            }
            finally {
                try { Stop-TcpChurnCollector $collector }
                catch { if ($null -eq $failure) { $failure=$_ } else { Write-Warning 'Owned collector diagnostic cleanup also failed.' } }
            }
        }
    }
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
    }
    $progress | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PublishDirectory 'cpu-progress.json')
}
$timing | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Diagnostics 'intervals.json')
if (-not $owned -or -not $progress.profileStopped) { throw $failure }
if (-not $timing.Contains('loadStart')) { throw $failure }
if ($eventOwned) {
    $null=Invoke-TcpChurnTool -Program $analyzer -Arguments @(
        '--events',$eventTrace,(Join-Path $PublishDirectory 'tcp-events.json'),'interval',
        $timing.loadStart,$timing.loadEnd,(Join-Path $PublishDirectory 'tcp-state.json')
    ) -Directory $Diagnostics -LogPrefix (Join-Path $Diagnostics 'probe-analysis') -TimeoutSeconds 120
}
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
if ($SynDrop) {
    [ordered]@{
        schema=1;workload='tcp-churn';outcome='observed-syn-failures';fault='scoped-silent-syn-drop'
        failedConnections=$totals.failedConnections;seconds=$totals.seconds
        clientSeconds=$progress.synOutcomes.Milliseconds/1000.0;loadAndAnalysisSeconds=$clock.Elapsed.TotalSeconds
        mechanismVerified=$false;conclusion='fault-observation-only'
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PublishDirectory 'result.json')
    Import-Module (Join-Path $PSScriptRoot 'CpuEvidence.psm1') -Force
    $evidence=Get-TcpChurnWaitEvidence `
        -Cpu (Get-Content -LiteralPath (Join-Path $PublishDirectory 'cpu-load.json') -Raw|ConvertFrom-Json) `
        -Events (Get-Content -LiteralPath (Join-Path $PublishDirectory 'tcp-events.json') -Raw|ConvertFrom-Json) `
        -Outcome (Get-Content -LiteralPath (Join-Path $PublishDirectory 'result.json') -Raw|ConvertFrom-Json)
    $evidence|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $PublishDirectory 'lock-evidence.json')
    if ($null -ne $PeerSession -and (-not $evidence.verifiedFault -or -not $evidence.queuedWaitObserved)) {
        throw 'The real-peer outage did not produce the required sampled queued-wait evidence.'
    }
} else {
    Export-TcpChurnPublicResult -Result ([pscustomobject]$totals) -Path (Join-Path $PublishDirectory 'result.json')
}
