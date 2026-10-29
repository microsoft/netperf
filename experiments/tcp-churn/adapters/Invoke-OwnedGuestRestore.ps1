# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 5.1
<#
Inventories, and optionally restores, resources owned by an interrupted managed-GC
guest run (for example a job cancelled at its timeout before its finally block ran).
Restoration replays the harness's own snapshot-based remove actions from the orphaned
run roots; only exclusively named firewall rules and the owned epoch-dial route are
removed by name. Nothing is removed by address pattern alone, and raw traces are kept.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][pscredential]$Credential,
    [Parameter(Mandatory)][string]$ReportFile,
    [switch]$Restore,
    [string]$VmName='netperf-windows-2022-client'
)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $ReportFile){throw 'Use a fresh numeric restore report.'}
$worker={
    param([pscredential]$PeerCredential,[bool]$Apply)
    $ErrorActionPreference='Stop'
    $pwsh=(Get-Command pwsh -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
    $inventory={
        $loggers=@(& logman.exe query -ets)
        [pscustomobject]@{
            aliases=@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop|Where-Object{$_.IPAddress -match '^198\.19\.240\.[1-6]$' -or $_.IPAddress -match '^198\.19\.6[4-7]\.'}).Count
            rules=@(Get-NetFirewallRule -PolicyStore ActiveStore -ErrorAction Stop|Where-Object{$_.Name -like 'ManagedGcPeer-*' -or $_.Name -like 'ManagedGcReceiver-*' -or $_.Name -like 'NetperfClusterOutage-*'}).Count
            staticNeighbors=@(Get-NetNeighbor -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|Where-Object{$_.IPAddress -match '^198\.19\.240\.[1-6]$' -and [string]$_.State -eq 'Permanent'}).Count
            routes=@(Get-NetRoute -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|Where-Object DestinationPrefix -in @('198.19.240.6/32','198.19.0.0/17','198.19.64.0/22','198.19.248.0/24')).Count
            recorderLoggers=@($loggers|Where-Object{$_ -match '^\s*(WPR_initiated_|TcpChurnExact-)'}).Count
            ownedAdapters=@(Get-NetAdapter -ErrorAction Stop|Where-Object Name -match '^Netperf(Path|Data)-[0-9a-f]{12}$').Count
        }
    }
    function Stop-OwnedProcess([string]$RootPattern) {
        $stopped=0
        foreach($p in @(Get-CimInstance Win32_Process -ErrorAction Stop|Where-Object{
            $_.ProcessId -ne $PID -and $_.Name -in @('ArrivalTcp.exe','CpuSamples.exe','pwsh.exe','dotnet.exe') -and
            ([string]$_.CommandLine -match $RootPattern -or [string]$_.ExecutablePath -match $RootPattern)})){
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue;$stopped++
        }
        $stopped
    }
    if(@(Get-Process -Name 'Runner.Worker','ctsTraffic' -ErrorAction Ignore).Count){throw 'The client guest has an active worker.'}
    $clientBefore=& $inventory
    $report=[ordered]@{schema=1;restoreRequested=$Apply;clientBefore=$clientBefore;clientProcessesStopped=0;clientRecorderSessionsStopped=0
        clientRootsRestored=0;clientDialRoutesRemoved=0;clientRulesRemoved=0;peerBefore=$null;peerProcessesStopped=0
        peerRootsRestored=0;peerRulesRemoved=0;clientAfter=$null;peerAfter=$null}
    if($Apply){
        $report.clientProcessesStopped=Stop-OwnedProcess '\\netperf-churn-[0-9a-f]{32}\\'
        foreach($row in @(& logman.exe query -ets)){
            if($row -match '^\s*((WPR_initiated_|TcpChurnExact-)\S+)'){
                & logman.exe stop $Matches[1] -ets *> $null
                if($LASTEXITCODE -eq 0){$report.clientRecorderSessionsStopped++}
            }
        }
        $roots=@(Get-ChildItem -LiteralPath $env:TEMP -Directory -Filter 'netperf-churn-*'|
            Where-Object{$_.Name -match '^netperf-churn-[0-9a-f]{32}$' -and -not($_.Attributes -band [IO.FileAttributes]::ReparsePoint)}|
            Sort-Object CreationTimeUtc -Descending)
        foreach($root in $roots){
            $diagnostics=Join-Path $root.FullName 'managed-gc-diagnostics'
            if(-not(Test-Path -LiteralPath $diagnostics -PathType Container)){continue}
            $routeState=Join-Path $diagnostics 'cluster-routes-original.clixml'
            $dataState=Join-Path $diagnostics 'data-original.clixml'
            $routePending=(Test-Path -LiteralPath $routeState) -and -not(Test-Path -LiteralPath (Join-Path $diagnostics 'cluster-routes-restored.json'))
            $dataPending=(Test-Path -LiteralPath $dataState) -and -not(Test-Path -LiteralPath (Join-Path $diagnostics 'data-restored.json'))
            if(-not $routePending -and -not $dataPending){continue}
            $owner=@(Get-NetIPAddress -AddressFamily IPv4 -IPAddress '198.19.240.1' -ErrorAction SilentlyContinue)
            if($owner.Count -ne 1){throw 'The owned client data address is not uniquely present for snapshot restoration.'}
            $alias=$owner[0].InterfaceAlias
            $scripts=Join-Path $root.FullName 'experiment'
            if($routePending){
                $script=@(Get-ChildItem -LiteralPath $scripts -Recurse -File -Filter 'Set-ScopedClusterRoutes.ps1')
                if($script.Count -ne 1){throw 'The orphaned run does not contain its route restore helper.'}
                & $pwsh -NoProfile -NonInteractive -File $script[0].FullName -Action remove -InterfaceAlias $alias `
                    -StateFile $routeState -ReportFile (Join-Path $diagnostics 'cluster-routes-restored.json')
                if($LASTEXITCODE){throw 'The orphaned cluster-route restore failed.'}
            }
            foreach($route in @(Get-NetRoute -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|Where-Object DestinationPrefix -eq '198.19.248.0/24')){
                Remove-NetRoute -InterfaceIndex $route.InterfaceIndex -DestinationPrefix '198.19.248.0/24' -PolicyStore ActiveStore -Confirm:$false -ErrorAction Stop
                $report.clientDialRoutesRemoved++
            }
            if($dataPending){
                $script=@(Get-ChildItem -LiteralPath $scripts -Recurse -File -Filter 'Set-ScopedDataAddresses.ps1')
                if($script.Count -ne 1){throw 'The orphaned run does not contain its address restore helper.'}
                & $pwsh -NoProfile -NonInteractive -File $script[0].FullName -Action remove -InterfaceAlias $alias `
                    -Addresses '198.19.240.1,198.19.240.2,198.19.240.3,198.19.240.4' -StateFile $dataState `
                    -ReportFile (Join-Path $diagnostics 'data-restored.json')
                if($LASTEXITCODE){throw 'The orphaned data-address restore failed.'}
            }
            $report.clientRootsRestored++
        }
        foreach($route in @(Get-NetRoute -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|Where-Object DestinationPrefix -eq '198.19.248.0/24')){
            Remove-NetRoute -InterfaceIndex $route.InterfaceIndex -DestinationPrefix '198.19.248.0/24' -PolicyStore ActiveStore -Confirm:$false -ErrorAction Stop
            $report.clientDialRoutesRemoved++
        }
        foreach($rule in @(Get-NetFirewallRule -PolicyStore ActiveStore -ErrorAction Stop|Where-Object{$_.Name -like 'ManagedGcReceiver-*' -or $_.Name -like 'ManagedGcPeer-*'})){
            Remove-NetFirewallRule -Name $rule.Name -PolicyStore ActiveStore -ErrorAction Stop;$report.clientRulesRemoved++
        }
    }
    $peer=New-PSSession -ComputerName netperf-peer -Credential $PeerCredential -ConfigurationName PowerShell.7 -ErrorAction Stop
    try {
        $peerResult=Invoke-Command -Session $peer -ErrorAction Stop -ScriptBlock {
            param($inventoryText,[bool]$Apply)
            $ErrorActionPreference='Stop'
            $inventory=[scriptblock]::Create($inventoryText)
            if(@(Get-Process -Name 'Runner.Worker','ctsTraffic' -ErrorAction Ignore).Count){throw 'The peer guest has an active worker.'}
            $result=[ordered]@{before=& $inventory;processesStopped=0;rootsRestored=0;rulesRemoved=0;after=$null}
            if($Apply){
                foreach($p in @(Get-CimInstance Win32_Process -ErrorAction Stop|Where-Object{
                    $_.ProcessId -ne $PID -and $_.Name -in @('ArrivalTcp.exe','pwsh.exe','dotnet.exe') -and
                    ([string]$_.CommandLine -match '\\managed-gc-peer-[0-9a-f]{32}\\' -or [string]$_.ExecutablePath -match '\\managed-gc-peer-[0-9a-f]{32}\\')})){
                    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue;$result.processesStopped++
                }
                foreach($rule in @(Get-NetFirewallRule -PolicyStore ActiveStore -ErrorAction Stop|Where-Object{$_.Name -like 'ManagedGcPeer-*' -or $_.Name -like 'NetperfClusterOutage-*' -or $_.Name -like 'ManagedGcReceiver-*'})){
                    Remove-NetFirewallRule -Name $rule.Name -PolicyStore ActiveStore -ErrorAction Stop;$result.rulesRemoved++
                }
                $roots=@(Get-ChildItem -LiteralPath $env:TEMP -Directory -Filter 'managed-gc-peer-*'|
                    Where-Object{$_.Name -match '^managed-gc-peer-[0-9a-f]{32}$' -and -not($_.Attributes -band [IO.FileAttributes]::ReparsePoint)}|
                    Sort-Object CreationTimeUtc -Descending)
                foreach($root in $roots){
                    $clusterState=Join-Path $root.FullName 'cluster-original.clixml'
                    $dataState=Join-Path $root.FullName 'data-original.clixml'
                    $clusterPending=(Test-Path -LiteralPath $clusterState) -and -not(Test-Path -LiteralPath (Join-Path $root.FullName 'cluster-restored.json'))
                    $dataPending=(Test-Path -LiteralPath $dataState) -and -not(Test-Path -LiteralPath (Join-Path $root.FullName 'data-restored.json'))
                    if(-not $clusterPending -and -not $dataPending){continue}
                    $owner=@(Get-NetIPAddress -AddressFamily IPv4 -IPAddress '198.19.240.6' -ErrorAction SilentlyContinue)
                    if($owner.Count -ne 1){throw 'The owned peer data address is not uniquely present for snapshot restoration.'}
                    $alias=$owner[0].InterfaceAlias
                    if($clusterPending){
                        & (Join-Path $root.FullName 'Set-ScopedClusterAddresses.ps1') -Action remove -InterfaceAlias $alias -Count 1000 `
                            -StateFile $clusterState -ReportFile (Join-Path $root.FullName 'cluster-restored.json')
                    }
                    if($dataPending){
                        & (Join-Path $root.FullName 'Set-ScopedDataAddresses.ps1') -Action remove -InterfaceAlias $alias `
                            -Addresses '198.19.240.5,198.19.240.6' -StateFile $dataState -ReportFile (Join-Path $root.FullName 'data-restored.json')
                    }
                    $result.rootsRestored++
                }
            }
            $result.after=& $inventory
            [pscustomobject]$result
        } -ArgumentList $inventory.ToString(),$Apply
    } finally {Remove-PSSession $peer}
    $report.peerBefore=$peerResult.before;$report.peerProcessesStopped=$peerResult.processesStopped
    $report.peerRootsRestored=$peerResult.rootsRestored;$report.peerRulesRemoved=$peerResult.rulesRemoved;$report.peerAfter=$peerResult.after
    $report.clientAfter=& $inventory
    [pscustomobject]$report
}
try{
    $report=Invoke-Command -VMName $VmName -Credential $Credential -ErrorAction Stop -ScriptBlock $worker -ArgumentList $Credential,([bool]$Restore)
    $clean=$true
    foreach($side in @($report.clientAfter,$report.peerAfter)){
        foreach($name in 'aliases','rules','staticNeighbors','routes','recorderLoggers','ownedAdapters'){if($side.$name -ne 0){$clean=$false}}
    }
    $report|Select-Object schema,restoreRequested,clientBefore,clientProcessesStopped,clientRecorderSessionsStopped,clientRootsRestored,
        clientDialRoutesRemoved,clientRulesRemoved,clientAfter,peerBefore,peerProcessesStopped,peerRootsRestored,peerRulesRemoved,peerAfter,
        @{n='ownedResourcesClear';e={$clean}},@{n='pathsExported';e={$false}},@{n='rawTracesExported';e={$false}}|
        Select-Object * -ExcludeProperty PSComputerName,RunspaceId,PSShowComputerName|
        ConvertTo-Json -Depth 4|Set-Content -LiteralPath $ReportFile
    if($Restore -and -not $clean){throw 'Owned resources remain after snapshot-based restoration.'}
}catch{
    if(-not(Test-Path -LiteralPath $ReportFile)){
        $message=$_.Exception.Message
        @{schema=1;outcome='failed';failureType=$_.Exception.GetType().FullName
            publicDiagnosticTerms=@('active','worker','restore','address','route','helper','unique','present','failed','access','denied','session'|
                Where-Object{$message -match ('(?i)\b'+[regex]::Escape($_)+'\b')})
            pathsExported=$false;rawTracesExported=$false}|ConvertTo-Json|Set-Content -LiteralPath $ReportFile
    }
    throw 'The bounded owned-resource restore failed; no private paths or raw traces were published.'
}
