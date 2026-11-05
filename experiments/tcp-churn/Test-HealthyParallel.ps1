# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'TcpChurn.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'adapters\WindowsCts.psm1') -Force
$module=Get-Module WindowsCts
$checks=0
foreach($workers in 1..8) {
    foreach($concurrency in @(64,256,1024)) {
        $plan=New-TcpChurnPlan -ClientAddress '192.0.2.21' -ServerAddress '192.0.2.12' -Connections $concurrency `
            -MaximumConnectionAttempts ([int][Math]::Floor(8192.0/$workers))
        if($plan.MaximumConnectionAttempts*$workers -gt 8192 -or $plan.MaximumConnectionAttempts -lt $concurrency) {
            throw 'Parallel source-port budget was exceeded or cannot cover a wave.'
        }
        $iterations=[int](($plan.ClientArguments|Where-Object{$_ -like '-iterations:*'}) -replace '^-iterations:','')
        if($iterations*$concurrency -ne $plan.MaximumConnectionAttempts -or $iterations -gt 32) {
            throw 'Declared attempt budget differs from actual CTS iterations.'
        }
        $checks++
    }
}
$rejected=$false
try { $null=New-TcpChurnPlan -ClientAddress '192.0.2.21' -ServerAddress '192.0.2.12' -Connections 256 -MaximumConnectionAttempts 128 }
catch { $rejected=$true }
if(-not $rejected) { throw 'An insufficient connection budget was accepted.' }
$checks++
try {
    & $module {
        function script:Start-ChurnChild($Program,$Arguments,$Directory,$LogPrefix) {
            $script:HealthyParallelTest.Starts++
            if($script:HealthyParallelTest.Case -eq 'partial-start' -and $script:HealthyParallelTest.Starts -eq 2) {
                throw 'Simulated partial server startup failure.'
            }
            $server=@($Arguments|Where-Object{$_ -like '-listen:*'}).Count -gt 0
            $exit=if($script:HealthyParallelTest.Case -in @('client-error','client-and-cleanup-error') -and -not $server){1}else{0}
            $text=if($script:HealthyParallelTest.Case -eq 'invalid-summary'){'invalid'}else{
                "SuccessfulConnections [2] NetworkErrors [0] ProtocolErrors [0]`nTotal Bytes Sent : 131072`nTotal Time : 10 ms"
            }
            @{Process=[pscustomobject]@{HasExited=(-not $server);ExitCode=$exit}
                Output=[Threading.Tasks.Task]::FromResult($text)}
        }
        function script:Test-WindowsChurnPeer($State,$Plan) { $true }
        function script:Read-WindowsChurnCounters($State,$Plan) {
            $script:HealthyParallelTest.Reads++
            $bytes=if($script:HealthyParallelTest.Reads -eq 1){0L}else{262144L}
            [pscustomobject]@{Transmitted=$bytes;Received=$bytes}
        }
        function script:Close-WindowsChurn($State,$Plan) {
            $script:HealthyParallelTest.Closes++
            if($script:HealthyParallelTest.Case -in @('cleanup-error','client-and-cleanup-error')) { throw 'Simulated cleanup failure.' }
        }
    }
    foreach($case in @('success','client-error','invalid-summary','partial-start','cleanup-error','client-and-cleanup-error')) {
        & $module { param($Case) $script:HealthyParallelTest=@{Case=$Case;Starts=0;Reads=0;Closes=0} } $case
        $directory=Join-Path ([IO.Path]::GetTempPath()) ('healthy-test-'+[guid]::NewGuid().ToString('N'))
        $null=New-Item -ItemType Directory -Path $directory
        try {
            $plans=@(1..2|ForEach-Object{
                New-TcpChurnPlan -ClientAddress "192.0.2.$(20+$_)" -ServerAddress '192.0.2.12' -Port (53617+$_)
            })
            $failed=$false;$result=$null
            try {
                $result=Invoke-WindowsChurnParallelBatch -Executable (Get-Process -Id $PID).Path `
                    -DiagnosticsDirectory $directory -ClientInterface 'test-A' -ServerInterface 'test-B' -Plans $plans
            } catch {
                $failed=$true
                if($case -eq 'client-and-cleanup-error' -and $_.Exception.InnerExceptions.Count -ne 3) {
                    throw 'Combined traffic and cleanup failures were not preserved.'
                }
            }
            $state=& $module { $script:HealthyParallelTest }
            if($failed -ne ($case -ne 'success')) { throw "Incorrect parallel outcome for $case." }
            if($state.Closes -ne 2) { throw "Partial/failure cleanup skipped an owned state for $case." }
            if($case -eq 'success' -and ($result.connections -ne 4 -or $result.bytesSent -ne 262144 -or
                $result.adapterTransmitDelta -ne 262144 -or $result.adapterReceiveDelta -ne 262144)) {
                throw 'Parallel result aggregation or shared-adapter accounting failed.'
            }
            $checks++
        } finally {
            foreach($name in @('worker-0','worker-1')) {
                $path=Join-Path $directory $name
                if(Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -ErrorAction Stop }
            }
            Remove-Item -LiteralPath $directory -ErrorAction Stop
        }
    }
} finally {
    Remove-Module WindowsCts -ErrorAction Stop
    Import-Module (Join-Path $PSScriptRoot 'adapters\WindowsCts.psm1') -Force
}
Write-Output "Passed $checks parallel healthy lifecycle cases; mocked data is not a contention reproduction."
