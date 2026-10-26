# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ScratchParent,
    [Parameter(Mandatory)][string]$PublishDirectory,
    [ValidateRange(5,120)][int]$Seconds=15,
    [ValidateRange(1,1024)][int]$Connections=16,
    [switch]$DedicatedLab,
    [switch]$ProfileCpu,
    [string]$AnalyzerDirectory
)
$ErrorActionPreference='Stop'
if (-not $DedicatedLab -or -not $IsWindows) { throw 'Provisioning requires an explicitly dedicated Windows lab.' }
$who=[Security.Principal.WindowsIdentity]::GetCurrent()
try {
    if (-not ([Security.Principal.WindowsPrincipal]::new($who)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Elevated lab execution is required.' }
} finally { $who.Dispose() }
$root=Split-Path $PSScriptRoot
Import-Module (Join-Path $root 'TcpChurn.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'WindowsCts.psm1') -Force
$existing=@(Get-NetAdapter -IncludeHidden -ErrorAction Stop)
if (@($existing | Where-Object { $_.InterfaceDescription -match '(?i)duonic' -or $_.Name -like 'duo?' }).Count) {
    throw 'Refusing to provision over existing DuoNIC devices or fixture aliases; use the manual adapter instead.'
}
if (@(Get-NetIPAddress -AddressFamily IPv4 -IncludeAllCompartments -ErrorAction Stop |
    Where-Object IPAddress -like '192.168.1.*').Count) {
    throw 'The public fixture subnet is already assigned; use a preconfigured manual fixture instead.'
}
if (Test-Path -LiteralPath $PublishDirectory) { throw 'Publish directory must be new.' }
New-Item -ItemType Directory -Path $PublishDirectory -ErrorAction Stop | Out-Null
$scratch=Join-Path $ScratchParent ('tcp-churn-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch -ErrorAction Stop | Out-Null
$tools=Join-Path $scratch 'tools'
$logs=Join-Path $scratch 'diagnostics'
New-Item -ItemType Directory -Path $logs -ErrorAction Stop | Out-Null
$owned=$false; $firewall=$false; $failure=$null; $result=$null
$rule='NetperfTcpChurn-'+[guid]::NewGuid().ToString('N')
$phase='acquire'
$observations=[ordered]@{
    adapterCount=0; upCount=0; aliasCount=0; preferredAddresses=0; cleanupErrors=0; toolExitCode=0
    publicCampaignErrorLine=0; publicErrorType='none'
}
try {
    $null=& (Join-Path $root 'Acquire-PublicTools.ps1') -Destination $tools
    $phase='install'
    $owned=$true
    $null=Invoke-TcpChurnTool -Program (Get-Process -Id $PID).Path -Arguments @(
        '-NoProfile','-File',(Join-Path $tools 'duonic.ps1'),'-Install','-NumNicPairs','1','-NoFirewallRules'
    ) -Directory $tools -LogPrefix (Join-Path $logs 'setup') -TimeoutSeconds 300
    if ($ProfileCpu) {
        $phase='rss-setup'
        # The pinned public DuoNIC package supports at most 16 RSS processors.
        # These adapters are newly created and exclusively fixture-owned.
        foreach ($alias in @('duo1','duo2')) {
            Set-NetAdapterRss -Name $alias -Enabled $true -BaseProcessorGroup 0 -BaseProcessorNumber 0 `
                -MaxProcessorGroup 0 -MaxProcessorNumber 15 -MaxProcessors 16 -NumberOfReceiveQueues 16 `
                -Profile ClosestStatic -ErrorAction Stop
        }
    }
    $phase='adapter-check'
    $nics=@(Get-NetAdapter -IncludeHidden -ErrorAction Stop | Where-Object InterfaceDescription -match '(?i)duonic')
    $observations.adapterCount=$nics.Count
    $observations.upCount=@($nics | Where-Object Status -eq 'Up').Count
    $observations.aliasCount=@($nics | Where-Object Name -in @('duo1','duo2')).Count
    if ($nics.Count -ne 2 -or @($nics | Where-Object Status -ne 'Up').Count -ne 0 -or
        @($nics | Where-Object Name -in @('duo1','duo2')).Count -ne 2) {
        throw 'Public fixture did not create the expected healthy pair.'
    }
    $phase='address-check'
    foreach ($binding in @(@('duo1','192.168.1.11'),@('duo2','192.168.1.12'))) {
        $dad=[Diagnostics.Stopwatch]::StartNew()
        do {
            $addresses=@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
                Where-Object { $_.InterfaceAlias -eq $binding[0] -and $_.IPAddress -eq $binding[1] -and $_.AddressState -eq 'Preferred' })
            if ($addresses.Count -eq 1) { break }
            if ($dad.Elapsed.TotalSeconds -ge 30) { throw 'DuoNIC addresses did not become Preferred after RSS reconfiguration.' }
            Start-Sleep -Milliseconds 200
        } while ($true)
        $observations.preferredAddresses+=$addresses.Count
        if ($addresses.Count -ne 1) {
            throw 'DuoNIC address postcondition failed.'
        }
    }
    if ($ProfileCpu) {
        $phase='source-addresses'
        foreach ($last in 21..28) {
            $address="192.168.1.$last"
            $null=New-NetIPAddress -InterfaceAlias duo1 -IPAddress $address -PrefixLength 24 -SkipAsSource $true -ErrorAction Stop
            $null=New-NetRoute -InterfaceAlias duo2 -DestinationPrefix "$address/32" -NextHop 0.0.0.0 -RouteMetric 0 -ErrorAction Stop
            $wait=[Diagnostics.Stopwatch]::StartNew()
            while (@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
                Where-Object { $_.IPAddress -eq $address -and $_.AddressState -eq 'Preferred' }).Count -ne 1) {
                if ($wait.Elapsed.TotalSeconds -gt 30) { throw 'Owned source address did not become Preferred.' }
                Start-Sleep -Milliseconds 200
            }
        }
    }
    $phase='firewall'
    $ports=if($ProfileCpu){'53617-53816'}else{'53617'}
    $remote=if($ProfileCpu){@('192.168.1.11')+@(21..28|ForEach-Object{"192.168.1.$_"})}else{@('192.168.1.11')}
    $null=New-NetFirewallRule -Name $rule -DisplayName $rule -Direction Inbound -Action Allow -Protocol TCP `
        -LocalPort $ports -LocalAddress 192.168.1.12 -RemoteAddress $remote -ErrorAction Stop
    $firewall=$true
    $phase='traffic'
    if ($ProfileCpu) {
        $phase='cpu-campaign'
        & (Join-Path $root 'Invoke-CpuCampaign.ps1') -Tools $tools -Diagnostics $logs `
            -PublishDirectory $PublishDirectory -AnalyzerDirectory $AnalyzerDirectory -Seconds $Seconds -Connections $Connections
        $result=Get-Content -LiteralPath (Join-Path $PublishDirectory 'result.json') -Raw | ConvertFrom-Json
    } else {
        $plan=New-TcpChurnPlan -ClientAddress 192.168.1.11 -ServerAddress 192.168.1.12 -Seconds $Seconds -Connections $Connections
        $adapter=New-WindowsCtsAdapter -Executable (Join-Path $tools 'ctsTraffic.exe') -DiagnosticsDirectory $logs `
            -ClientInterface duo1 -ServerInterface duo2
        $result=Invoke-TcpChurnExperiment -Plan $plan -Adapter $adapter
    }
} catch {
    $failure=$_
    $observations.publicErrorType=$_.Exception.GetType().FullName
    if ($_.ScriptStackTrace -match 'Invoke-CpuCampaign\.ps1: line (\d+)') {
        $observations.publicCampaignErrorLine=[int]$Matches[1]
    }
    if ($_.Exception.Data.Contains('ToolExitCode')) { $observations.toolExitCode=[int]$_.Exception.Data['ToolExitCode'] }
} finally {
    $cleanup=[Collections.Generic.List[Exception]]::new()
    if ($firewall) {
        try { Remove-NetFirewallRule -Name $rule -ErrorAction Stop }
        catch { $cleanup.Add($_.Exception) }
    }
    if ($owned) {
        foreach ($instance in @('duonic_svc1','duonic_svc2')) {
            try {
                $null=Invoke-TcpChurnTool -Program (Join-Path $tools 'dswdevice.exe') -Arguments @('-u',$instance) `
                    -Directory $tools -LogPrefix (Join-Path $logs $instance) -TimeoutSeconds 30
            } catch { $cleanup.Add($_.Exception) }
        }
        try {
            $wait=[Diagnostics.Stopwatch]::StartNew()
            while (@(Get-NetAdapter -IncludeHidden -ErrorAction Stop | Where-Object InterfaceDescription -match '(?i)duonic').Count) {
                if ($wait.Elapsed.TotalSeconds -gt 30) { throw 'Owned DuoNIC devices remain after removal.' }
                Start-Sleep -Milliseconds 200
            }
        } catch { $cleanup.Add($_.Exception) }
    }
    if ($cleanup.Count) {
        $observations.cleanupErrors=$cleanup.Count
        if ($null -ne $failure) { $cleanup.Add($failure.Exception) }
        $failure=[AggregateException]::new('Lab cleanup failed.',$cleanup)
    }
}
if ($null -ne $failure) {
    [ordered]@{schema=1;workload='tcp-churn';outcome='failed';phase=$phase;observations=$observations;conclusion='no-measurement'} |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $PublishDirectory 'result.json') -Encoding utf8
    throw "TCP churn failed during $phase or cleanup. Raw diagnostics stay on the runner and are not publication artifacts."
}
if (-not $ProfileCpu) { Export-TcpChurnPublicResult -Result $result -Path (Join-Path $PublishDirectory 'result.json') }
Write-Output 'Collected numeric TCP churn results; CPU coverage and target mechanism are not verified.'
