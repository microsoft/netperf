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

function Get-TcpHealthyWaitEvidence {
    param(
        [Parameter(Mandatory)]$Cpu,[Parameter(Mandatory)]$Events,[Parameter(Mandatory)]$Outcome,
        [ValidateSet('public','private-lab-only')][string]$SymbolScope='public'
    )
    if($Outcome.outcome -ne 'collected' -or $Outcome.connections -le 0 -or $Outcome.bytesSent -le 0) {
        throw 'Only completed healthy traffic can provide success-scenario evidence.'
    }
    if($Cpu.outcome -ne 'sampled' -or $Events.outcome -ne 'counted' -or $Cpu.eventsLost -ne 0 -or $Events.eventsLost -ne 0) {
        throw 'Lossless CPU samples and exact-event counts are required.'
    }
    $waits=[ordered]@{pathInfoAckTracking=0L;pathInfoShutdownRtt=0L;pathInfoConnectionFailure=0L
        pathInfoOther=0L;pathLookupOrValidation=0L;wfp=0L;endpointPortAllocation=0L;other=0L}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($function in $Cpu.publicNetworkFunctionCallers) {
        foreach($stack in $function.stacks) {
            $name=[string]$stack.name
            if(-not $seen.Add($name)) { continue }
            if($name -notmatch '^nt!(?:KeYieldProcessorEx <- nt!)?(?:KxWaitForLockOwnerShip|KxWaitForSpinLockAndAcquire) <- (?:nt![^<]+ <- )*tcpip!(?<owner>[^ <]+)') { continue }
            $owner=$Matches.owner
            $bucket=if($owner -eq 'IpNlpSetPathInfo') {
                if($name -match 'tcpip!InetSetPathConnectionFailedAf') { 'pathInfoConnectionFailure' }
                elseif($name -match 'tcpip!(?:InetSetPathInfoRttAf|TcpShutdownTcb)') { 'pathInfoShutdownRtt' }
                elseif($name -match 'tcpip![^ <]*(?:BhDetect|BlackHole|SetPathBH|ConfirmForwardReachability)') { 'pathInfoAckTracking' }
                else { 'pathInfoOther' }
            } elseif($owner -in @('IppFindOrCreatePath','IppValidatePath','IppValidatePathUnderLock')) { 'pathLookupOrValidation' }
            elseif($owner -match '^(?:Wfp|CheckConnectBypass)') { 'wfp' }
            elseif($owner -match '^InetAcquire.*Port') { 'endpointPortAllocation' }
            else { 'other' }
            $waits[$bucket]+=[long]$stack.samples
        }
    }
    [pscustomobject][ordered]@{
        schema=1;scenario='healthy-no-injected-loss';symbolScope=$SymbolScope
        successfulConnections=[long]$Outcome.connections;cpuSamples=[long]$Cpu.cpuSamples
        unresolvedNetworkFrames=[long]$Cpu.unresolvedNetworkFrames
        waitSamplesLowerBound=[pscustomobject]$waits
        pathInfoWaitObserved=(($waits.pathInfoAckTracking+$waits.pathInfoShutdownRtt+$waits.pathInfoConnectionFailure+$waits.pathInfoOther) -gt 0)
        healthyPathInfoWaitObserved=(($waits.pathInfoAckTracking+$waits.pathInfoShutdownRtt+$waits.pathInfoOther) -gt 0)
        connectionFailurePathObserved=($waits.pathInfoConnectionFailure -gt 0)
        fullSizeAckEvents=[long]$Events.publicProbeCounts.TcpBhDetectFullSizeAck
        blackHoleProbeEntryEvents=[long]$Events.publicProbeCounts.TcpBlackHoleDetectionEntry
        timeoutEvents=[long]$Events.publicProbeCounts.TcpDisconnectTcbRtoTimeout
        retransmissionRoundEvents=[long]$Events.publicProbeCounts.TcpDataTransferRetransmitRound
        classification='bounded-stack-lower-bounds-not-lock-address-proof'
        conclusion='success-scenario-sampling-not-performance-improvement'
    }
}

Export-ModuleMember -Function Get-TcpChurnWaitEvidence,Get-TcpHealthyWaitEvidence
