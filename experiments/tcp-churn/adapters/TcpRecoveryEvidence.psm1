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
function Read-TcpRecoveryEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Provider,
        [Parameter(Mandatory)][string]$TracePath,
        [Parameter(Mandatory)][datetime]$StartUtc,
        [Parameter(Mandatory)][datetime]$EndUtc,
        [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$OwnerProcessId,
        [Parameter(Mandatory)][ValidateRange(1,8192)][int]$ExpectedConnections
    )
    $start=$StartUtc.ToUniversalTime();$end=$EndUtc.ToUniversalTime()
    if($end -le $start){throw 'A positive TCP owner-evidence interval is required.'}
    $layouts=@{}
    foreach($metadata in $Provider.Events) {
        if($null -eq $metadata.Task -or $metadata.Task.Name -notin @('TcpConnectTcbComplete','TcpInsertConnectionTuple','TcpCloseTcbRequest',
            'TcpDataTransferRetransmitRound','TcpBlackHoleDetectionEntry','TcpBlackHoleDetectionExit','TcpBlackHoleDetectionFailed','TcpBhDetectFullSizeAck')){continue}
        $template=[xml]$metadata.Template
        $names=@($template.GetElementsByTagName('data','http://schemas.microsoft.com/win/2004/08/events')|ForEach-Object{$_.GetAttribute('name')})
        $tcb=[array]::IndexOf($names,'Tcb');$pidIndex=[array]::IndexOf($names,'ProcessId')
        $status=[array]::IndexOf($names,'Status');$reason=[array]::IndexOf($names,'TraceString')
        if($tcb -lt 0 -or ($metadata.Task.Name -eq 'TcpConnectTcbComplete' -and ($pidIndex -lt 0 -or $status -lt 0)) -or
            ($metadata.Task.Name -eq 'TcpBlackHoleDetectionFailed' -and $reason -lt 0)){
            throw 'The public TCP manifest lacks required owner/lifetime correlation fields.'
        }
        $layouts[([string]$metadata.Id+':'+$metadata.Version)]=@{task=$metadata.Task.Name;tcb=$tcb;pid=$pidIndex;status=$status;reason=$reason}
    }
    $rows=[Collections.Generic.List[object]]::new()
    Get-WinEvent -Path $TracePath -Oldest|ForEach-Object{
        $key=[string]$_.Id+':'+$_.Version
        if($_.TimeCreated.ToUniversalTime() -ge $start -and $_.TimeCreated.ToUniversalTime() -le $end -and $layouts.ContainsKey($key)){
            if($rows.Count -ge 200000){throw 'TCP owner/lifetime evidence exceeded its bound.'}
            $layout=$layouts[$key]
            $owner=if($layout.pid -ge 0){[uint32]$_.Properties[$layout.pid].Value}else{0}
            $status=if($layout.status -ge 0){[uint32]$_.Properties[$layout.status].Value}else{0}
            $ack=if($layout.reason -ge 0){[regex]::IsMatch([string]$_.Properties[$layout.reason].Value,'(?i)\bACK\b')}else{$false}
            $rows.Add([pscustomobject]@{kind=$layout.task;tcb=[uint64]$_.Properties[$layout.tcb].Value
                processId=$owner;status=$status;timestampTicks=$_.TimeCreated.ToUniversalTime().Ticks;failureReasonAckToken=$ack})
        }
    }
    Get-TcpRecoveryCounts -Records $rows.ToArray() -OwnerProcessId $OwnerProcessId -ExpectedConnections $ExpectedConnections
}
Export-ModuleMember -Function Get-TcpRecoveryCounts,Read-TcpRecoveryEvidence
