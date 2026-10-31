# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-TcpChurnPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ClientAddress,
        [Parameter(Mandatory)][string]$ServerAddress,
        [ValidateRange(1024,65535)][int]$Port=53617,
        [ValidateRange(1,4096)][int]$Connections=16,
        [ValidateRange(1,8192)][int]$MaximumConnectionAttempts=8192,
        [ValidateRange(5,900)][int]$Seconds=15,
        [ValidateRange(65536,16777216)][int]$BytesPerConnection=65536
    )
    foreach ($address in @($ClientAddress,$ServerAddress)) {
        $parsed=$null
        if (-not [Net.IPAddress]::TryParse($address,[ref]$parsed) -or
            $parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or
            [Net.IPAddress]::IsLoopback($parsed) -or $parsed.GetAddressBytes()[0] -eq 0 -or
            $parsed.GetAddressBytes()[0] -ge 224) {
            throw 'Endpoints must be non-loopback unicast IPv4 addresses.'
        }
    }
    if ($ClientAddress -eq $ServerAddress) { throw 'Distinct endpoint addresses are required.' }
    if($Connections -gt $MaximumConnectionAttempts) { throw 'The connection budget must cover one concurrent wave.' }
    # Bound this deployment smoke below a typical ephemeral-port range. Sustained
    # churn needs an explicit port-reuse/resource budget, not silent OS tuning.
    $iterations=[int][Math]::Min(32,[Math]::Floor([double]$MaximumConnectionAttempts/$Connections))
    $base=@('-protocol:tcp','-pattern:push',"-port:$Port","-transfer:$BytesPerConnection")
    [pscustomobject]@{
        Schema=1; Seconds=$Seconds; Port=$Port; Connections=$Connections
        MaximumConnectionAttempts=$Connections*$iterations
        ClientAddress=$ClientAddress; ServerAddress=$ServerAddress
        ClientArguments=$base + @("-bind:$ClientAddress","-target:$ServerAddress","-connections:$Connections","-iterations:$iterations","-TimeLimit:$($Seconds*1000)")
        ServerArguments=$base + @("-listen:$ServerAddress","-TimeLimit:$(($Seconds+30)*1000)")
    }
}

function ConvertFrom-CtsChurnOutput {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)
    # Format source: microsoft/ctsTraffic, ctsTraffic/ctsTraffic.cpp.
    $counts=[regex]::Matches($Text,'SuccessfulConnections\s*\[(?<ok>\d+)\]\s+NetworkErrors\s*\[(?<net>\d+)\]\s+ProtocolErrors\s*\[(?<protocol>\d+)\]')
    $bytes=[regex]::Matches($Text,'Total Bytes Sent\s*:\s*(\d+)')
    $time=[regex]::Matches($Text,'Total Time\s*:\s*(\d+)\s*ms')
    if (-not $counts.Count -or -not $bytes.Count -or -not $time.Count) {
        throw 'Incomplete or incompatible CTS summary.'
    }
    $last=$counts[$counts.Count-1].Groups
    $value=[pscustomobject]@{
        Completed=[long]$last['ok'].Value
        NetworkErrors=[long]$last['net'].Value
        ProtocolErrors=[long]$last['protocol'].Value
        SentBytes=[long]$bytes[$bytes.Count-1].Groups[1].Value
        Milliseconds=[long]$time[$time.Count-1].Groups[1].Value
    }
    if ($value.Milliseconds -le 0) { throw 'Non-positive CTS measurement interval.' }
    $value
}

function Invoke-TcpChurnExperiment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Adapter,
        [ValidateRange(1,60)][int]$ReadyTimeoutSeconds=20,
        [ValidateRange(0,30)][int]$DrainSeconds=5
    )
    # The adapter owns resources. The module owns the experiment and its invariants.
    foreach ($method in @('StartPeer','PeerReady','ReadCounters','RunClient','Close')) {
        if (-not $Adapter.Contains($method) -or $Adapter[$method] -isnot [scriptblock]) {
            throw "Adapter method $method is required."
        }
    }
    if (-not $Adapter.Contains('State')) { throw 'Adapter State is required.' }
    $failure=$null
    $result=$null
    try {
        $null=& $Adapter.StartPeer $Adapter.State $Plan
        $wait=[Diagnostics.Stopwatch]::StartNew()
        while (-not (& $Adapter.PeerReady $Adapter.State $Plan)) {
            if ($wait.Elapsed.TotalSeconds -ge $ReadyTimeoutSeconds) { throw 'Peer readiness deadline exceeded.' }
            Start-Sleep -Milliseconds 100
        }
        $before=& $Adapter.ReadCounters $Adapter.State $Plan
        $execution=& $Adapter.RunClient $Adapter.State $Plan
        if ($execution.ExitCode -ne 0) { throw 'Traffic command failed; diagnostics belong to the adapter.' }
        $summary=ConvertFrom-CtsChurnOutput $execution.Text
        if ($summary.Completed -le 0 -or $summary.SentBytes -le 0 -or
            $summary.NetworkErrors -ne 0 -or $summary.ProtocolErrors -ne 0) {
            throw 'Healthy churn did not complete error-free traffic.'
        }
        $drain=[Diagnostics.Stopwatch]::StartNew()
        do {
            $after=& $Adapter.ReadCounters $Adapter.State $Plan
            $tx=[long]$after.Transmitted-[long]$before.Transmitted
            $rx=[long]$after.Received-[long]$before.Received
            if ($tx -ge $summary.SentBytes -and $rx -ge $summary.SentBytes) { break }
            if ($drain.Elapsed.TotalSeconds -ge $DrainSeconds) { throw 'Data was not accounted for on the selected adapters.' }
            Start-Sleep -Milliseconds 100
        } while ($true)
        $elapsed=$summary.Milliseconds/1000.0
        # This is intentionally not a host inventory, trace, binary, or private build record.
        $result=[pscustomobject][ordered]@{
            schema=1; workload='tcp-churn'; outcome='collected'
            connections=$summary.Completed; seconds=$elapsed; bytesSent=$summary.SentBytes
            connectionsPerSecond=$summary.Completed/$elapsed
            megabitsPerSecond=8.0*$summary.SentBytes/1000000.0/$elapsed
            adapterTransmitDelta=$tx; adapterReceiveDelta=$rx
            cpuCoverage='not-measured'; targetBranchCoverage='not-measured'
            mechanismVerified=$false; conclusion='collection-only'
        }
    } catch {
        $failure=$_
    } finally {
        try { $null=& $Adapter.Close $Adapter.State $Plan }
        catch {
            if ($null -ne $failure) {
                throw [AggregateException]::new('Experiment and adapter cleanup failed.',[Exception[]]@($failure.Exception,$_.Exception))
            }
            throw
        }
    }
    if ($null -ne $failure) { throw $failure }
    $result
}

function Export-TcpChurnPublicResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Result,[Parameter(Mandatory)][string]$Path)
    # Reconstruct an allowlist; never serialize adapter State or arbitrary extensions.
    $safe=[ordered]@{}
    foreach ($key in @('schema','workload','outcome','connections','seconds','bytesSent','connectionsPerSecond',
        'megabitsPerSecond','adapterTransmitDelta','adapterReceiveDelta','cpuCoverage','targetBranchCoverage',
        'mechanismVerified','conclusion')) {
        $safe[$key]=$Result.$key
    }
    if ($safe.schema -ne 1 -or $safe.workload -ne 'tcp-churn' -or $safe.outcome -ne 'collected' -or
        $safe.cpuCoverage -ne 'not-measured' -or $safe.targetBranchCoverage -ne 'not-measured' -or
        $safe.mechanismVerified -ne $false -or $safe.conclusion -ne 'collection-only') {
        throw 'Unsupported public result contract.'
    }
    foreach ($key in @('connections','seconds','bytesSent','connectionsPerSecond','megabitsPerSecond','adapterTransmitDelta','adapterReceiveDelta')) {
        if ($safe[$key] -is [string] -or -not [double]::IsFinite([double]$safe[$key]) -or [double]$safe[$key] -le 0) {
            throw "Invalid numeric result $key."
        }
    }
    if (Test-Path -LiteralPath $Path) { throw 'Refusing to overwrite a published result.' }
    $safe | ConvertTo-Json | Set-Content -LiteralPath $Path -Encoding utf8
}

Export-ModuleMember -Function New-TcpChurnPlan,ConvertFrom-CtsChurnOutput,Invoke-TcpChurnExperiment,Export-TcpChurnPublicResult
