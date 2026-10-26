# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-TcpChurnWaitEvidence {
    param([Parameter(Mandatory)]$Cpu,[Parameter(Mandatory)]$Events,[Parameter(Mandatory)]$Outcome)
    if ($Cpu.outcome -ne 'sampled' -or $Events.outcome -ne 'counted' -or
        $Cpu.eventsLost -ne 0 -or $Events.eventsLost -ne 0) {
        throw 'Lossless CPU samples and exact-event counts are required.'
    }
    $wait=0L
    foreach ($function in $Cpu.publicNetworkFunctionCallers) {
        if ($function.function -ne 'tcpip!IpNlpSetPathInfo') { continue }
        foreach ($stack in $function.stacks) {
            if ($stack.name -match 'nt!(?:KeYieldProcessorEx <- nt!)?KxWaitForLockOwnerShip <- nt!KeAcquireInStackQueuedSpinLock <- tcpip!IpNlpSetPathInfo <- tcpip!InetSetPathConnectionFailedAf <- tcpip!TcpNotifyTcbDelay') {
                $wait+=[long]$stack.samples
            }
        }
    }
    $timeouts=[long]$Events.publicProbeCounts.TcpDisconnectTcbRtoTimeout
    $rounds=[long]$Events.publicProbeCounts.TcpDataTransferRetransmitRound
    [pscustomobject][ordered]@{
        schema=1;signal='public-symbol-cpu-samples-and-events'
        case='connection-failure-path-info-update'
        verifiedFault=($Outcome.outcome -eq 'observed-syn-failures' -and $timeouts -gt 0 -and $rounds -gt 0)
        queuedWaitObserved=($wait -gt 0);queuedWaitSamplesLowerBound=$wait
        connectionTimeoutEvents=$timeouts;retransmissionRoundEvents=$rounds
        blackHoleProbeEntryEvents=[long]$Events.publicProbeCounts.TcpBlackHoleDetectionEntry
        fullSizeAckEvents=[long]$Events.publicProbeCounts.TcpBhDetectFullSizeAck
        conclusion='reproduction-evidence-not-performance-improvement'
    }
}

Export-ModuleMember -Function Get-TcpChurnWaitEvidence
