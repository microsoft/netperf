# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'TcpChurn.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'adapters\WindowsCts.psm1') -Force
$script:count=0
function Check([bool]$Value,[string]$Message) {
    if (-not $Value) { throw $Message }
    $script:count++
}
function Reject([scriptblock]$Action) {
    $caught=$false
    try { $null=& $Action } catch { $caught=$true }
    Check $caught 'An invalid operation was accepted.'
}
function New-FakeAdapter {
    @{
        State=@{
            Started=$false; Closed=$false; Reads=0; BadWire=$false; FailStart=$false; FailClose=$false
            Text="SuccessfulConnections [12] NetworkErrors [0] ProtocolErrors [0]`nTotal Bytes Sent : 131072`nTotal Time : 2000 ms."
        }
        StartPeer={param($s,$p) $s.Started=$true; if($s.FailStart){throw 'start failure'}}
        PeerReady={param($s,$p) $true}
        ReadCounters={param($s,$p)
            $s.Reads++
            $v=if($s.Reads -gt 1 -and -not $s.BadWire){200000}else{0}
            [pscustomobject]@{Transmitted=$v;Received=$v}
        }
        RunClient={param($s,$p) [pscustomobject]@{ExitCode=0;Text=$s.Text}}
        Close={param($s,$p) $s.Closed=$true; if($s.FailClose){throw 'close failure'}}
    }
}
$work=Join-Path ([IO.Path]::GetTempPath()) ('tcp-churn-tests-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -ErrorAction Stop | Out-Null
try {
    $plan=New-TcpChurnPlan -ClientAddress 192.0.2.10 -ServerAddress 192.0.2.11
    Check ($plan.ClientArguments -contains '-TimeLimit:15000') 'CTS duration must be milliseconds.'
    Check ($plan.ClientArguments -contains '-bind:192.0.2.10') 'Explicit bind missing.'
    Check ($plan.ServerArguments -contains '-listen:192.0.2.11') 'Explicit listener missing.'
    Check ($plan.ClientArguments -contains '-iterations:32') 'Unbounded connection churn in deployment smoke.'
    $wide=New-TcpChurnPlan -ClientAddress 192.0.2.10 -ServerAddress 192.0.2.11 -Connections 4096
    Check ($wide.MaximumConnectionAttempts -le 8192) 'Ephemeral-port smoke budget exceeded.'
    Reject { New-TcpChurnPlan -ClientAddress 127.0.0.1 -ServerAddress 192.0.2.11 }
    Reject { New-TcpChurnPlan -ClientAddress 192.0.2.10 -ServerAddress 192.0.2.10 }
    Reject { New-TcpChurnPlan -ClientAddress ::1 -ServerAddress 192.0.2.11 }
    Reject { New-TcpChurnPlan -ClientAddress 0.0.0.0 -ServerAddress 192.0.2.11 }
    Reject { New-TcpChurnPlan -ClientAddress 192.0.2.10 -ServerAddress 224.1.2.3 }
    Reject { New-TcpChurnPlan -ClientAddress 192.0.2.10 -ServerAddress 192.0.2.11 -Seconds 0 }
    Reject { ConvertFrom-CtsChurnOutput 'startup failure' }
    $fake=New-FakeAdapter
    $result=Invoke-TcpChurnExperiment -Plan $plan -Adapter $fake -DrainSeconds 0
    Check ($fake.State.Started -and $fake.State.Closed) 'Adapter lifecycle incomplete.'
    Check ($result.connections -eq 12 -and $result.connectionsPerSecond -eq 6) 'Incorrect summary arithmetic.'
    Check (-not $result.mechanismVerified -and $result.conclusion -eq 'collection-only') 'Unsupported performance claim.'
    $fake=New-FakeAdapter; $fake.State.BadWire=$true
    Reject { Invoke-TcpChurnExperiment -Plan $plan -Adapter $fake -DrainSeconds 0 }
    Check $fake.State.Closed 'Wire rejection leaked the adapter.'
    $fake=New-FakeAdapter; $fake.State.FailStart=$true
    Reject { Invoke-TcpChurnExperiment -Plan $plan -Adapter $fake }
    Check $fake.State.Closed 'Partial start did not close.'
    $fake=New-FakeAdapter; $fake.State.FailClose=$true
    Reject { Invoke-TcpChurnExperiment -Plan $plan -Adapter $fake -DrainSeconds 0 }
    $fake=New-FakeAdapter; $fake.State.Text=$fake.State.Text.Replace('NetworkErrors [0]','NetworkErrors [1]')
    Reject { Invoke-TcpChurnExperiment -Plan $plan -Adapter $fake -DrainSeconds 0 }
    $fake=New-FakeAdapter; $fake.Remove('ReadCounters')
    Reject { Invoke-TcpChurnExperiment -Plan $plan -Adapter $fake }
    $result | Add-Member NoteProperty ArbitraryDiagnostic 'DO_NOT_PUBLISH'
    $published=Join-Path $work 'result.json'
    Export-TcpChurnPublicResult -Result $result -Path $published
    $text=Get-Content -LiteralPath $published -Raw
    Check (-not $text.Contains('DO_NOT_PUBLISH') -and -not $text.Contains('192.0.2.')) 'Publication leaked adapter data.'
    Reject { Export-TcpChurnPublicResult -Result $result -Path $published }
    $result.megabitsPerSecond='DO_NOT_PUBLISH'
    Reject { Export-TcpChurnPublicResult -Result $result -Path (Join-Path $work 'bad.json') }
    $lock=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'dependencies.json') -Raw | ConvertFrom-Json
    Check ($lock.assets.Count -eq 6) 'Unexpected dependency surface.'
    foreach ($asset in $lock.assets) {
        Check ($asset.url -match '^https://raw\.githubusercontent\.com/microsoft/(ctsTraffic|corenet-ci)/[a-f0-9]{40}/') 'Unpinned/nonpublic asset.'
        Check ($asset.sha256 -match '^[A-Fa-f0-9]{64}$') 'Missing asset integrity.'
    }
    $child=Join-Path $work 'argument probe.ps1'
    [IO.File]::WriteAllText($child,'param([string]$Value) if($Value -ne "one literal argument"){exit 3}; [Console]::Out.WriteLine("ok")')
    $null=Invoke-TcpChurnTool -Program (Get-Process -Id $PID).Path -Arguments @(
        '-NoProfile','-File',$child,'one literal argument'
    ) -Directory $work -LogPrefix (Join-Path $work 'child') -TimeoutSeconds 15
    Check ((Get-Content -LiteralPath (Join-Path $work 'child.out.txt') -Raw).Trim() -eq 'ok') 'Native argument boundary failed.'
    $windows=New-WindowsCtsAdapter -Executable (Get-Process -Id $PID).Path -DiagnosticsDirectory $work `
        -ClientInterface fixture1 -ServerInterface fixture2
    $localPlan=[pscustomobject]@{ ServerArguments=@('-NoProfile','-Command','Start-Sleep -Seconds 20') }
    try {
        $null=& $windows.StartPeer $windows.State $localPlan
        Check (-not $windows.State.Server.Process.HasExited) 'Windows callback did not start its owned child.'
    } finally { $null=& $windows.Close $windows.State $localPlan }
    Check ($null -eq $windows.State.Server) 'Cross-module adapter cleanup did not reset owned state.'
    Check (Test-Path -LiteralPath (Join-Path $work 'server.out.txt')) 'Adapter diagnostics were not local.'
    Write-Output "Passed $script:count public-source checks."
} finally {
    # Only this explicitly created, uniquely named test directory is removed.
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction Stop
}
