# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'CpuEvidence.psm1') -Force
$outcome=[pscustomobject]@{outcome='collected';connections=10;bytesSent=655360}
$events=[pscustomobject]@{outcome='counted';eventsLost=0;publicProbeCounts=[pscustomobject]@{
    TcpBhDetectFullSizeAck=9;TcpBlackHoleDetectionEntry=0;TcpDisconnectTcbRtoTimeout=0;TcpDataTransferRetransmitRound=0;TcpTcbSynSend=0
}}
$cpu=[pscustomobject]@{outcome='sampled';cpuSamples=100;eventsLost=0;unresolvedNetworkFrames=0;publicNetworkFunctionCallers=@()}
$prefix='nt!KxWaitForSpinLockAndAcquire <- nt!KxAcquireSpinLock <- '
$stacks=@(
    [pscustomobject]@{name=$prefix+'tcpip!IpNlpSetPathInfo <- tcpip!InetSetPathInfoRttAf <- tcpip!TcpShutdownTcb';samples=2}
    [pscustomobject]@{name=$prefix+'tcpip!IpNlpSetPathInfo <- tcpip!TcpBhDetectFullSizeAck';samples=3}
    [pscustomobject]@{name=$prefix+'tcpip!WfpAleClassify <- tcpip!TcpReceive';samples=5}
    [pscustomobject]@{name='nt!KxWaitForLockOwnerShip <- nt!KeAcquireInStackQueuedSpinLock <- tcpip!InetAcquireWildcardPortUnderLock';samples=7}
    [pscustomobject]@{name='nt!KeAcquireSpinLockRaiseToDpc <- tcpip!IpNlpSetPathInfo <- tcpip!TcpShutdownTcb';samples=101}
    [pscustomobject]@{name='tcpip!IpNlpSetPathInfo <- tcpip!TcpBhDetectFullSizeAck';samples=103}
)
$cpu.publicNetworkFunctionCallers=@(
    [pscustomobject]@{function='tcpip!first';stacks=$stacks}
    [pscustomobject]@{function='tcpip!duplicate-callers';stacks=$stacks}
)
$r=Get-TcpHealthyWaitEvidence -Cpu $cpu -Events $events -Outcome $outcome
if($r.waitSamplesLowerBound.pathInfoShutdownRtt -ne 2 -or $r.waitSamplesLowerBound.pathInfoAckTracking -ne 3 -or
    $r.waitSamplesLowerBound.wfp -ne 5 -or $r.waitSamplesLowerBound.endpointPortAllocation -ne 7) {
    throw 'Wait classification duplicated stacks, counted acquisition-only frames or mixed callers.'
}
$checks=1
$cpu.publicNetworkFunctionCallers[0].stacks=@($stacks[4],$stacks[5])
$cpu.publicNetworkFunctionCallers[1].stacks=@()
$r=Get-TcpHealthyWaitEvidence -Cpu $cpu -Events $events -Outcome $outcome
if($r.pathInfoWaitObserved -or $r.fullSizeAckEvents -ne 9) { throw 'Tracking events or acquisition frames were mistaken for waiting.' }
$checks++
$cpu.publicNetworkFunctionCallers[0].stacks=@(
    [pscustomobject]@{name=$prefix+'tcpip!IpNlpSetPathInfo <- tcpip!InetSetPathConnectionFailedAf <- tcpip!TcpNotifyTcbDelay';samples=1}
)
$r=Get-TcpHealthyWaitEvidence -Cpu $cpu -Events $events -Outcome $outcome
if(-not $r.connectionFailurePathObserved -or $r.healthyPathInfoWaitObserved) {
    throw 'Application success concealed a sampled connection-failure update.'
}
$checks++
$cpu.publicNetworkFunctionCallers=@(
    [pscustomobject]@{function='tcpip!IpNlpSetPathInfo';stacks=@(
        [pscustomobject]@{name='nt!KeReleaseInStackQueuedSpinLock <- tcpip!IpNlpSetPathInfo <- tcpip!ExampleSetPathBH <- tcpip!TcpNotifyTcbDelay';samples=4}
    )}
)
$r=Get-TcpHealthyWaitEvidence -Cpu $cpu -Events $events -Outcome $outcome
if($r.ackConfirmationPathSamplesLowerBound -ne 4 -or $r.healthyPathInfoWaitObserved) {
    throw 'Confirmation-path execution was mistaken for a sampled wait.'
}
$checks++
foreach($kind in @('failed','cpu-loss','event-loss')) {
    $outcome.outcome='collected';$cpu.eventsLost=0;$events.eventsLost=0
    switch($kind) { failed {$outcome.outcome='failed'} cpu-loss {$cpu.eventsLost=1} event-loss {$events.eventsLost=1} }
    $rejected=$false
    try { $null=Get-TcpHealthyWaitEvidence -Cpu $cpu -Events $events -Outcome $outcome } catch { $rejected=$true }
    if(-not $rejected) { throw "Invalid healthy evidence accepted: $kind." }
    $checks++
}
Write-Output "Passed $checks healthy wait-evidence cases."
