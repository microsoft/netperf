# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Get-TcpRecoveryCounts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Records,
        [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$OwnerProcessId,
        [Parameter(Mandatory)][ValidateRange(1,8192)][int]$ExpectedConnections
    )
    $owners=@{};$completed=0;$closed=0;$ackFailures=0;$last=[long]::MinValue
    $counts=[ordered]@{TcpDataTransferRetransmitRound=0;TcpBlackHoleDetectionEntry=0
        TcpBlackHoleDetectionExit=0;TcpBlackHoleDetectionFailed=0;TcpBhDetectFullSizeAck=0}
    foreach($record in $Records) {
        if($record.timestampTicks -lt $last){throw 'TCP lifetime evidence must be chronological.'}
        $last=$record.timestampTicks
        if($record.tcb -le 0){throw 'A positive private TCB identity is required.'}
        $key=[string]$record.tcb
        switch($record.kind) {
            TcpInsertConnectionTuple {$owners.Remove($key)}
            TcpCloseTcbRequest {
                if($owners.ContainsKey($key) -and $owners[$key]){$closed++}
                $owners.Remove($key)
            }
            TcpConnectTcbComplete {
                $owned=$record.status -eq 0 -and $record.processId -eq $OwnerProcessId
                $owners[$key]=$owned
                if($owned){$completed++}
            }
            default {
                if(-not $counts.Contains($record.kind)){throw 'An unsupported TCP evidence task was supplied.'}
                if($owners.ContainsKey($key) -and $owners[$key]){
                    $counts[$record.kind]++
                    if($record.kind -eq 'TcpBlackHoleDetectionFailed' -and $record.failureReasonAckToken){$ackFailures++}
                }
            }
        }
    }
    if($completed -ne $ExpectedConnections){throw 'Owned-process TCP completion coverage did not match the verified workload.'}
    if($closed -ne $ExpectedConnections){throw 'Owned-process TCP closure coverage did not match the verified workload.'}
    [pscustomobject]@{schema=1;processAndLifetimeFilterApplied=$true;ownedConnectionCompletions=$completed
        ownedConnectionClosures=$closed;failedAttemptReasonMentionsAckToken=$ackFailures
        publicProbeCounts=$counts;scope='owned-client-only';conclusion='algorithm-coverage-not-lock-wait-proof'}
}
Export-ModuleMember -Function Get-TcpRecoveryCounts
