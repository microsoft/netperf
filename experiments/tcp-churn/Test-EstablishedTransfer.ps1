# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'TcpChurn.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'adapters\WindowsCts.psm1') -Force
$module=Get-Module WindowsCts
$checks=0
try {
    & $module {
        function script:Start-Sleep { param($Seconds,$Milliseconds) }
        function script:Start-ChurnChild {
            $process=[pscustomobject]@{HasExited=($script:EstablishedTest.Case -eq 'early-exit');Id=123;ExitCode=0}
            $process|Add-Member -MemberType ScriptMethod -Name WaitForExit -Value {
                param($timeout) $this.HasExited=$true;return $true
            }
            @{Process=$process;Output=[Threading.Tasks.Task]::FromResult(
                "SuccessfulConnections [2] NetworkErrors [0] ProtocolErrors [0]`nTotal Bytes Sent : 131072`nTotal Time : 10 ms"
            )}
        }
        function script:Get-NetTCPConnection {
            param($State,$ErrorAction)
            $script:EstablishedTest.ConnectionReads++
            $count=if($script:EstablishedTest.Case -eq 'closed-inside' -and $script:EstablishedTest.ConnectionReads -eq 2){1}else{2}
            foreach($i in 1..$count) { [pscustomobject]@{OwningProcess=123;RemotePort=20000} }
        }
        function script:Read-WindowsChurnCounters {
            $script:EstablishedTest.CounterReads++
            $n=$script:EstablishedTest.CounterReads
            $bytes=if($script:EstablishedTest.Case -eq 'no-progress'){0}else{($n-1)*131072L}
            [pscustomobject]@{Transmitted=$bytes;Received=$bytes}
        }
    }
    foreach($case in @('success','early-exit','closed-inside','no-progress','measurement-failure')) {
        & $module { param($Case) $script:EstablishedTest=@{Case=$Case;CounterReads=0;ConnectionReads=0} } $case
        $state=@{Client=$null;Server=$null;Executable='mock';Directory='mock';Closes=0}
        $adapter=@{State=$state
            StartPeer={param($state,$plan) $state.Server=@{Process=[pscustomobject]@{HasExited=$false}}}
            PeerReady={param($state,$plan) $true}
            Close={param($state,$plan) $state.Closes++}
        }
        $plan=New-TcpChurnPlan -ClientAddress '192.0.2.21' -ServerAddress '192.0.2.12' -Port 20000 -Connections 2
        $measurement=@{establishedAtStart=0;establishedAtEnd=0;transmittedBytes=0L;receivedBytes=0L;Measured=$false;Case=$case}
        $failed=$false
        try {
            $result=Invoke-WindowsEstablishedTransfer -Adapter $adapter -Plan $plan -MeasurementState $measurement -Measure {
                param($value)
                if($value.Case -eq 'measurement-failure') { throw 'Simulated capture failure.' }
                $value.Measured=$true
            }
        } catch { $failed=$true }
        if($failed -ne ($case -ne 'success') -or $state.Closes -ne 1) { throw "Incorrect established lifecycle for $case." }
        if($case -eq 'success' -and ($measurement.establishedAtStart -ne 2 -or $measurement.establishedAtEnd -ne 2 -or
            $measurement.transmittedBytes -ne 131072 -or $result.bytesSent -ne 131072)) {
            throw 'Steady-state counts, wire progress or completed payload accounting are incorrect.'
        }
        $checks++
    }
} finally {
    Remove-Module WindowsCts
    Import-Module (Join-Path $PSScriptRoot 'adapters\WindowsCts.psm1') -Force
}
Write-Output "Passed $checks established-transfer lifecycle cases."
