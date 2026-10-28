# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'adapters\TcpRecoveryEvidence.psm1') -Force
function Record($Kind,$Tcb,$Process=0,$Status=0) {
    [pscustomobject]@{kind=$Kind;tcb=$Tcb;processId=$Process;status=$Status;timestampTicks=1;failureReasonAckToken=$true}
}
$records=@(
    (Record TcpConnectTcbComplete 1 10),
    (Record TcpBlackHoleDetectionEntry 1),
    (Record TcpCloseTcbRequest 1),
    (Record TcpBlackHoleDetectionEntry 1),
    (Record TcpConnectTcbComplete 2 20),
    (Record TcpBlackHoleDetectionEntry 2),
    (Record TcpInsertConnectionTuple 1),
    (Record TcpBlackHoleDetectionEntry 1),
    (Record TcpConnectTcbComplete 1 20),
    (Record TcpBlackHoleDetectionEntry 1),
    (Record TcpInsertConnectionTuple 2),
    (Record TcpConnectTcbComplete 2 10),
    (Record TcpDataTransferRetransmitRound 2),
    (Record TcpBlackHoleDetectionEntry 2),
    (Record TcpBlackHoleDetectionExit 2),
    (Record TcpBhDetectFullSizeAck 2),
    (Record TcpBlackHoleDetectionFailed 2),
    (Record TcpCloseTcbRequest 2)
)
$r=Get-TcpRecoveryCounts -Records $records -OwnerProcessId 10 -ExpectedConnections 2
if($r.publicProbeCounts.TcpBlackHoleDetectionEntry -ne 2 -or
    $r.publicProbeCounts.TcpDataTransferRetransmitRound -ne 1 -or
    $r.publicProbeCounts.TcpBlackHoleDetectionExit -ne 1 -or $r.publicProbeCounts.TcpBhDetectFullSizeAck -ne 1 -or
    $r.publicProbeCounts.TcpBlackHoleDetectionFailed -ne 1 -or $r.failedAttemptReasonMentionsAckToken -ne 1 -or
    $r.ownedConnectionClosures -ne 2 -or -not $r.processAndLifetimeFilterApplied){throw 'Management-traffic exclusion or TCB reuse attribution failed.'}
$checks=1
foreach($case in @('wrong-owner','wrong-count','missing-close','out-of-order','invalid-tcb','unknown-task')) {
    $inputRecords=@($records);$owner=10;$expected=2
    switch($case) {
        wrong-owner {$owner=30}
        wrong-count {$expected=3}
        missing-close {$inputRecords=@($records|Where-Object kind -ne 'TcpCloseTcbRequest')}
        out-of-order {$inputRecords=@((Record TcpConnectTcbComplete 1 10),(Record TcpBlackHoleDetectionEntry 1));$inputRecords[0].timestampTicks=2}
        invalid-tcb {$inputRecords=@((Record TcpConnectTcbComplete 0 10))}
        unknown-task {$inputRecords=@((Record unknown 1))}
    }
    $rejected=$false
    try {$null=Get-TcpRecoveryCounts -Records $inputRecords -OwnerProcessId $owner -ExpectedConnections $expected}
    catch {
        $pattern=switch($case) {
            out-of-order {'must be chronological'}
            invalid-tcb {'positive private TCB'}
            unknown-task {'unsupported TCP evidence task'}
            missing-close {'closure coverage did not match'}
            default {'completion coverage did not match'}
        }
        if($_.Exception.Message -notmatch $pattern){throw}
        $rejected=$true
    }
    if(-not $rejected){throw "Invalid TCP attribution input was accepted: $case"}
    $checks++
}
Write-Output "Passed $checks TCP recovery attribution cases; no trace identities, process IDs, or addresses were exported."
