# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$VmName,
    [Parameter(Mandatory)][pscredential]$Credential,
    [Parameter(Mandatory)][string]$PublishDirectory,
    [ValidateRange(1,120)][int]$Seconds=15,
    [ValidateRange(1,1024)][int]$Connections=16,
    [switch]$ProfileCpu,
    [string]$AnalyzerDirectory,
    [switch]$SynDrop,
    [switch]$ProbePeer,
    [switch]$PeerMeasurement,
    [switch]$ManagedGc,
    [ValidateRange(1,1048576)][int]$ManagedGcPayloadBytes=65536,
    [switch]$ManagedGcPeerRecovery,
    [switch]$ManagedGcIsolatedData,
    [ValidateRange(100,8000)][int]$ManagedGcRecoveryMilliseconds=8000,
    [ValidateSet('client','server')][string]$ManagedGcProcessRole='client',
    [ValidateSet('arrays','graph')][string]$ManagedGcHeapLayout='arrays',
    [switch]$ManagedGcRouteRefresh,
    [ValidateSet('onlink','peer-gateway')][string]$ManagedGcRouteVariant='onlink',
    [ValidateSet(0,16384)][int]$ManagedGcReceiveBudgetBytes=0,
    [ValidateSet(0,1024,8192,24576)][int]$ManagedGcCacheRetirePaths=0,
    [switch]$ManagedGcWprProbes,
    [switch]$ManagedGcPeerPressure,
    [switch]$ManagedGcUnusedInterface,
    [switch]$ManagedGcSpinLocks,
    [ValidateSet(0,32,40,64,80)][int]$ManagedGcRssProcessors=0,
    [switch]$ManagedGcOwnedDataInterface
)
$ErrorActionPreference='Stop'
if($ManagedGcOwnedDataInterface -and (-not $ManagedGc -or -not $ManagedGcIsolatedData -or -not $ManagedGcRssProcessors)){
    throw 'Disposable data transport requires isolated managed-GC mode and an explicit RSS count.'
}
if($ManagedGcRssProcessors -and -not $ManagedGc){throw 'Scoped RSS requires managed-GC diagnostic mode.'}
if($ManagedGcSpinLocks -and (-not $ManagedGc -or -not $ManagedGcWprProbes)){
    throw 'Owned spinlock capture requires managed-GC mode and the exact-event WPR controller.'
}
if($ManagedGcUnusedInterface -and (-not $ManagedGc -or $ManagedGcProcessRole -ne 'server' -or
    -not $ManagedGcIsolatedData -or -not $ManagedGcCacheRetirePaths -or $ManagedGcPeerRecovery)){
    throw 'Unused-interface retirement requires bounded isolated receiver-GC mode.'
}
if($ManagedGcWprProbes -and -not $ManagedGc){throw 'Exact WPR probes require managed-GC diagnostic mode.'}
if($ManagedGcPeerPressure -and (-not $ManagedGc -or $ManagedGcProcessRole -ne 'server' -or
    -not $ManagedGcIsolatedData -or $ManagedGcPeerRecovery)){
    throw 'Peer GC pressure requires isolated receiver-GC mode without a neighbor fault.'
}
if($ManagedGc -and (-not $ProfileCpu -or $SynDrop -or $ProbePeer -or $PeerMeasurement)){
    throw 'Managed-GC diagnostics require CPU profiling and are separate from peer probes and fault campaigns.'
}
if($PSBoundParameters.ContainsKey('ManagedGcPayloadBytes') -and -not $ManagedGc){
    throw 'Managed-GC payload selection requires managed-GC diagnostic mode.'
}
if($Seconds -lt 5 -and -not $ManagedGc){throw 'Intervals below five seconds require managed-GC diagnostic mode.'}
if($ManagedGcPeerRecovery -and -not $ManagedGc){throw 'Peer recovery requires managed-GC diagnostic mode.'}
if($ManagedGcIsolatedData -and -not $ManagedGc){throw 'Isolated data addresses require managed-GC diagnostic mode.'}
if($ManagedGcProcessRole -eq 'server' -and (-not $ManagedGc -or -not $ManagedGcIsolatedData -or $ManagedGcPeerRecovery)){
    throw 'Receiver GC requires managed-GC mode, isolated data and no neighbor pulse.'
}
if($ManagedGcHeapLayout -ne 'arrays' -and -not $ManagedGc){throw 'GC heap layout selection requires managed-GC diagnostic mode.'}
if($ManagedGcReceiveBudgetBytes -and (-not $ManagedGc -or $ManagedGcProcessRole -ne 'server')){
    throw 'A bounded receive budget requires receiver-GC diagnostic mode.'
}
if($ManagedGcCacheRetirePaths -and (-not $ManagedGc -or $ManagedGcProcessRole -ne 'server' -or
    -not $ManagedGcIsolatedData -or $ManagedGcPeerRecovery)){
    throw 'Cache retirement requires isolated receiver-GC mode without a neighbor fault.'
}
if($ManagedGcRouteRefresh -and (-not $ManagedGc -or $ManagedGcProcessRole -ne 'server' -or -not $ManagedGcIsolatedData -or $ManagedGcPeerRecovery)){
    throw 'Route refresh requires isolated receiver-GC mode without a neighbor pulse.'
}
if($ManagedGcRouteVariant -ne 'onlink' -and -not $ManagedGcRouteRefresh){throw 'Logical gateway selection requires the owned route-refresh control.'}
if($PSBoundParameters.ContainsKey('ManagedGcRecoveryMilliseconds') -and -not $ManagedGcPeerRecovery){
    throw 'Recovery duration selection requires managed-GC peer recovery.'
}
if (Test-Path -LiteralPath $PublishDirectory) { throw 'Use a new publication directory.' }
New-Item -ItemType Directory -Path $PublishDirectory -ErrorAction Stop | Out-Null
$session=$null; $guestRoot=$null; $phase='guest-connect'; $success=$false; $startup=$null
$vmFixture=$null;$fixtureAlias='';$fixtureGuid=''
$dataFixture=$null;$dataAlias='';$dataGuid=''
$rssAttempted=$false;$rssEvidence=$null
$vmFixtureState=Join-Path $PublishDirectory 'owned-vm-path-interface.clixml'
$dataFixtureState=Join-Path $PublishDirectory 'owned-vm-data-interface.clixml'
try {
    $vmInfo=Get-VM -Name $VmName -ErrorAction Stop
    if ($vmInfo.State -ne 'Running') {
        throw 'The documented guest must already be running; this adapter does not reset other workloads.'
    }
    $session=New-PSSession -VMName $VmName -Credential $Credential -ErrorAction Stop
    if ($ProbePeer) {
        $phase='peer-connectivity'
        $peerResult=Invoke-Command -Session $session -ErrorAction Stop -ScriptBlock {
            param($credential)
            if (@(Get-Process -Name 'Runner.Worker','ctsTraffic','ArrivalTcp','CpuSamples' -ErrorAction Ignore).Count) { throw 'Client guest is busy.' }
            $probePrefix=Join-Path $env:TEMP ('netperf-wpr-status-'+[guid]::NewGuid().ToString('N'))
            $probeOut=$probePrefix+'.out';$probeErr=$probePrefix+'.err'
            try{
                $query=Start-Process -FilePath "$env:SystemRoot\System32\wpr.exe" -ArgumentList '-status' `
                    -RedirectStandardOutput $probeOut -RedirectStandardError $probeErr -PassThru -NoNewWindow
                $null=$query.Handle
                if(-not $query.WaitForExit(15000)){
                    $query.Kill()
                    throw 'The read-only WPR status query exceeded its deadline.'
                }
                $query.WaitForExit()
                $query.Refresh()
                $wprExit=$query.ExitCode
                if($null -eq $wprExit){throw 'The read-only WPR query did not return an exit code.'}
                $status=(Get-Content -LiteralPath $probeOut -Raw)+(Get-Content -LiteralPath $probeErr -Raw)
                $wprNotRunning=$status -match '(?i)wpr is not recording|recording is not running'
                $wprCpu=$status -match '(?im)^\s*CPU(?:\.|\s*$)'
            }finally{
                foreach($file in @($probeOut,$probeErr)){if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file}}
            }
            $loggerRows=@(& "$env:SystemRoot\System32\logman.exe" query -ets)
            if($LASTEXITCODE -ne 0){throw 'The read-only ETW session query failed.'}
            $exactLoggers=@($loggerRows|Where-Object{$_ -match '^\s*TcpChurnExact-[0-9a-fA-F]{32}\s'}).Count
            $clientAliases=@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop|Where-Object{$_.IPAddress -match '^198\.19\.240\.[1-6]$' -or $_.IPAddress -eq '198.19.0.1'}).Count
            $clientPathInterfaces=@(Get-NetAdapter -ErrorAction Stop|Where-Object Name -match '^NetperfPath-[0-9a-f]{12}$').Count
            $clientDataInterfaces=@(Get-NetAdapter -ErrorAction Stop|Where-Object Name -match '^NetperfData-[0-9a-f]{12}$').Count
            $clientRules=@(Get-NetFirewallRule -PolicyStore ActiveStore -ErrorAction Stop|Where-Object{$_.Name -like 'ManagedGcPeer-*' -or $_.Name -like 'ManagedGcReceiver-*'}).Count
            $clientStatic=@(Get-NetNeighbor -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|
                Where-Object{$_.IPAddress -match '^198\.19\.240\.[1-6]$' -and [string]$_.State -eq 'Permanent'}).Count
            $clientRoutes=@(Get-NetRoute -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|Where-Object DestinationPrefix -in @('198.19.240.6/32','198.19.0.0/17')).Count
            if($clientAliases -or $clientRules -or $clientStatic -or $clientRoutes -or $clientPathInterfaces -or $clientDataInterfaces){throw 'Owned client GC resources require restoration before further tests.'}
            $clientCpus=(Get-CimInstance Win32_Processor|Measure-Object NumberOfLogicalProcessors -Sum).Sum
            $peerIp=@([Net.Dns]::GetHostAddresses('netperf-peer')|Where-Object AddressFamily -eq InterNetwork)[0].ToString()
            $dataRoute=@(Find-NetRoute -RemoteIPAddress $peerIp -ErrorAction Stop|Where-Object{$_.PSObject.Properties['IPAddress']})
            if($dataRoute.Count -ne 1){throw 'The read-only RSS probe requires one source route.'}
            $rss=@(Get-NetAdapterRss -Name $dataRoute[0].InterfaceAlias -ErrorAction Stop)
            if($rss.Count -ne 1){throw 'The read-only RSS probe requires one supported data-adapter RSS configuration.'}
            $clientFree=[Math]::Floor(([IO.DriveInfo]::new([IO.Path]::GetPathRoot($env:TEMP))).AvailableFreeSpace/1MB)
            if($clientCpus -lt 1){throw 'The client processor inventory did not return a positive count.'}
            $peer=New-PSSession -ComputerName netperf-peer -Credential $credential -ConfigurationName PowerShell.7 -ErrorAction Stop
            try {
                $peerState=Invoke-Command -Session $peer -ErrorAction Stop -ScriptBlock {
                    if (@(Get-Process -Name 'Runner.Worker','ctsTraffic','ArrivalTcp','CpuSamples' -ErrorAction Ignore).Count) { throw 'Peer guest is busy.' }
                    $aliases=@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop|Where-Object{$_.IPAddress -match '^198\.19\.240\.[1-6]$'}).Count
                    $rules=@(Get-NetFirewallRule -PolicyStore ActiveStore -ErrorAction Stop|Where-Object{$_.Name -like 'ManagedGcPeer-*' -or $_.Name -like 'ManagedGcReceiver-*'}).Count
                    $static=@(Get-NetNeighbor -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|
                        Where-Object{$_.IPAddress -match '^198\.19\.240\.[1-6]$' -and [string]$_.State -eq 'Permanent'}).Count
                    $routes=@(Get-NetRoute -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|Where-Object DestinationPrefix -eq '198.19.240.6/32').Count
                    if($aliases -or $rules -or $static -or $routes){throw 'Owned peer GC resources require restoration before further tests.'}
                    [pscustomobject]@{cpus=(Get-CimInstance Win32_Processor|Measure-Object NumberOfLogicalProcessors -Sum).Sum
                        aliases=$aliases;rules=$rules;static=$static;routes=$routes
                        tempFreeMiB=[Math]::Floor(([IO.DriveInfo]::new([IO.Path]::GetPathRoot($env:TEMP))).AvailableFreeSpace/1MB)}
                }
                $peerCpus=$peerState.cpus
                if($peerCpus -lt 1){throw 'The peer processor inventory did not return a positive count.'}
                [pscustomobject]@{schema=1;peerConnected=$true;clientLogicalProcessors=[int]$clientCpus;peerLogicalProcessors=[int]$peerCpus
                    clientOwnedAliases=$clientAliases;peerOwnedAliases=$peerState.aliases;clientOwnedRules=$clientRules;peerOwnedRules=$peerState.rules
                    clientOwnedStaticPeers=$clientStatic;peerOwnedStaticPeers=$peerState.static
                    clientTempFreeMiB=$clientFree;peerTempFreeMiB=$peerState.tempFreeMiB
                    clientWprStatusExitCode=$wprExit;clientWprRecordingNotRunning=[bool]$wprNotRunning
                    clientWprCpuProfileReported=[bool]$wprCpu
                    clientExactProbeLoggerCount=$exactLoggers
                    clientOwnedPathInterfaces=$clientPathInterfaces
                    clientOwnedDataInterfaces=$clientDataInterfaces
                    clientDataRssEnabled=[bool]$rss[0].Enabled
                    clientDataRssQueues=[int]$rss[0].NumberOfReceiveQueues
                    clientDataRssMaxProcessors=[int]$rss[0].MaxProcessors
                    clientDataRssProcessorArrayCount=@($rss[0].RssProcessorArray).Count
                    clientOwnedControlRoutes=$clientRoutes;peerOwnedControlRoutes=$peerState.routes;conclusion='connectivity-and-owned-resource-check'}
            } finally { Remove-PSSession $peer -ErrorAction Stop }
        } -ArgumentList $Credential
        $peerResult|Add-Member NoteProperty profiledVmGeneration ([int]$vmInfo.Generation)
        $peerResult|Add-Member NoteProperty profiledVmConnectedAdapters (@(Get-VMNetworkAdapter -VMName $VmName -ErrorAction Stop|Where-Object SwitchName).Count)
        $peerResult|Select-Object schema,peerConnected,profiledVmGeneration,profiledVmConnectedAdapters,clientLogicalProcessors,peerLogicalProcessors,clientOwnedAliases,peerOwnedAliases,
            clientOwnedRules,peerOwnedRules,clientOwnedStaticPeers,peerOwnedStaticPeers,clientOwnedControlRoutes,peerOwnedControlRoutes,
            clientWprStatusExitCode,clientWprRecordingNotRunning,clientWprCpuProfileReported,
            clientExactProbeLoggerCount,
            clientOwnedPathInterfaces,
            clientOwnedDataInterfaces,
            clientDataRssEnabled,clientDataRssQueues,clientDataRssMaxProcessors,clientDataRssProcessorArrayCount,
            clientTempFreeMiB,peerTempFreeMiB,conclusion|ConvertTo-Json |
            Set-Content -LiteralPath (Join-Path $PublishDirectory 'peer-check.json') -Encoding utf8
        return
    }
    $phase='guest-idle-check'
    $guestRoot=Invoke-Command -Session $session -ErrorAction Stop -ScriptBlock {
        if (@(Get-Process -Name 'Runner.Worker','ctsTraffic','ArrivalTcp','CpuSamples' -ErrorAction Ignore).Count) {
            throw 'Guest has an active Actions worker or CTS process.'
        }
        $root=Join-Path $env:TEMP ('netperf-churn-'+[guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -ErrorAction Stop | Out-Null
        $root
    }
    if($ManagedGcUnusedInterface){
        $phase='owned-vm-path-interface'
        Import-Module (Join-Path $PSScriptRoot 'VmPathFixture.psm1') -Force
        $vmFixture=New-TcpChurnVmPathFixture -VmName $VmName -Session $session -StateFile $vmFixtureState
        $fixtureAlias=$vmFixture.Alias;$fixtureGuid=$vmFixture.Guid
    }
    $phase='guest-copy'
    $localRoot=Split-Path $PSScriptRoot
    $remoteRoot=Join-Path $guestRoot 'experiment'
    $null=Invoke-Command -Session $session -ErrorAction Stop -ScriptBlock {
        param($path)
        New-Item -ItemType Directory -Path (Join-Path $path 'adapters') -Force -ErrorAction Stop | Out-Null
    } -ArgumentList $remoteRoot
    $sourceFiles=@('TcpChurn.psm1','CpuEvidence.psm1','Acquire-PublicTools.ps1','dependencies.json','Invoke-CpuCampaign.ps1')
    if($ManagedGc){$sourceFiles+=@('ArrivalTcp.cs','ArrivalTcp.ServerGc.config')}
    foreach ($file in $sourceFiles) {
        Copy-Item -LiteralPath (Join-Path $localRoot $file) -Destination (Join-Path $remoteRoot $file) -ToSession $session -ErrorAction Stop
    }
    if ($ProfileCpu) {
        Copy-Item -LiteralPath $AnalyzerDirectory -Destination (Join-Path $guestRoot 'analyzer') `
            -Recurse -ToSession $session -ErrorAction Stop
    }
    $adapterFiles=@('WindowsCts.psm1','Invoke-NetperfTcpChurn.ps1','Invoke-NetperfPeerCpu.ps1')
    if($ManagedGc){$adapterFiles+=@('Invoke-ManagedGcPeerDiagnostic.ps1','Invoke-ManagedGcGuestEntry.ps1','Invoke-ScopedNeighborPulse.ps1','TcpRecoveryEvidence.psm1','Set-ScopedDataAddresses.ps1','GcReceiverTraffic.psm1','Invoke-ScopedPathRefresh.ps1','Invoke-ScopedPathRetirement.ps1','New-GcProbeWprProfile.ps1','Set-ScopedRss.ps1')}
    foreach ($file in $adapterFiles) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination (Join-Path $remoteRoot "adapters\$file") -ToSession $session -ErrorAction Stop
    }
    if($ManagedGcOwnedDataInterface){
        $phase='owned-vm-data-interface'
        Import-Module (Join-Path $PSScriptRoot 'VmPathFixture.psm1') -Force
        $dataFixture=New-TcpChurnVmPathFixture -VmName $VmName -Session $session -StateFile $dataFixtureState `
            -Purpose data -GuestRoot $guestRoot -RssProcessors $ManagedGcRssProcessors
        $dataAlias=$dataFixture.Alias;$dataGuid=$dataFixture.Guid
    }
    if($ManagedGcRssProcessors -and -not $ManagedGcOwnedDataInterface){
        $phase='guest-scoped-rss-prepare';$rssAttempted=$true
        $rssEvidence=Invoke-Command -Session $session -ErrorAction Stop -ScriptBlock {
            param($root,$processors)
            $peer=@([Net.Dns]::GetHostAddresses('netperf-peer')|Where-Object AddressFamily -eq InterNetwork)[0].ToString()
            $route=@(Find-NetRoute -RemoteIPAddress $peer -ErrorAction Stop|Where-Object{$_.PSObject.Properties['IPAddress']})
            if($route.Count -ne 1){throw 'The RSS control requires one verified peer-route interface.'}
            & (Join-Path $root 'experiment\adapters\Set-ScopedRss.ps1') -Action prepare -Processors $processors `
                -InterfaceAlias $route[0].InterfaceAlias `
                -StateFile (Join-Path $root 'rss-original.clixml') -ReportFile (Join-Path $root 'rss-prepared.json')
            Get-Content -LiteralPath (Join-Path $root 'rss-prepared.json') -Raw|ConvertFrom-Json
        } -ArgumentList $guestRoot,$ManagedGcRssProcessors|Select-Object schema,action,verified,adapterRestarted,queues,maxProcessors,
            activeProcessorArrayCount,originalQueues,originalMaxProcessors,originalAddressesAndDefaultsPreserved,carriesDefaultRoute
    }
    $phase='guest-traffic'
    $exit=Invoke-Command -Session $session -ErrorAction Stop -ScriptBlock {
        param($root,$seconds,$connections,$profile,$synDrop,$peerMeasurement,$managedGc,$managedGcPayloadBytes,$peerRecovery,$isolatedData,$recoveryMilliseconds,$gcProcessRole,$heapLayout,$routeRefresh,$routeVariant,$receiveBudgetBytes,$cacheRetirePaths,$wprProbes,$peerPressure,$fixtureAlias,$fixtureGuid,$spinLocks,$dataAlias,$dataGuid,$credential)
        if (@(Get-Process -Name 'Runner.Worker','ctsTraffic' -ErrorAction Ignore).Count) {
            throw 'Guest became busy before traffic setup.'
        }
        $program=Join-Path $root 'experiment\adapters\Invoke-NetperfTcpChurn.ps1'
        # Native diagnostics remain inside the guest, never in public logs/artifacts.
        $extra=@()
        $credentialFile=$null
        if ($peerMeasurement -or $managedGc) {
            $program=Join-Path $root $(if($managedGc){'experiment\adapters\Invoke-ManagedGcGuestEntry.ps1'}else{'experiment\adapters\Invoke-NetperfPeerCpu.ps1'})
            $credentialFile=Join-Path $root 'peer-credential.clixml'
            # DPAPI-protected for this same account/machine; child deletes it immediately on import.
            $credential|Export-Clixml -LiteralPath $credentialFile -ErrorAction Stop
            $extra=@('-CredentialFile',$credentialFile,'-AnalyzerDirectory',(Join-Path $root 'analyzer'))
            if($managedGc){$extra+=@('-PayloadBytes',[string]$managedGcPayloadBytes)}
            if($peerRecovery){$extra+='-PeerRecovery'}
            if($isolatedData){$extra+='-IsolatedData'}
            if($peerRecovery){$extra+=@('-RecoveryMilliseconds',[string]$recoveryMilliseconds)}
            if($managedGc){$extra+=@('-GcProcessRole',$gcProcessRole)}
            if($managedGc){$extra+=@('-HeapLayout',$heapLayout)}
            if($receiveBudgetBytes){$extra+=@('-ReceiveBudgetBytes',[string]$receiveBudgetBytes)}
            if($cacheRetirePaths){$extra+=@('-CacheRetirePaths',[string]$cacheRetirePaths)}
            if($wprProbes){$extra+='-WprProbes'}
            if($peerPressure){$extra+='-PeerGcPressure'}
            if($spinLocks){$extra+='-SpinLocks'}
            if($fixtureAlias){$extra+=@('-CacheInterfaceAlias',$fixtureAlias,'-CacheInterfaceGuid',$fixtureGuid)}
            if($dataAlias){$extra+=@('-DataInterfaceAlias',$dataAlias,'-DataInterfaceGuid',$dataGuid)}
            if($routeRefresh){$extra+='-RouteRefresh'}
            if($routeRefresh){$extra+=@('-RouteVariant',$routeVariant)}
        } else {
            $extra=@('-DedicatedLab')
            if ($profile) { $extra+=@('-ProfileCpu','-AnalyzerDirectory',(Join-Path $root 'analyzer')) }
        }
        if ($synDrop) { $extra+='-SynDrop' }
        $launch=[ordered]@{managedGc=[bool]$managedGc;peerMeasurement=[bool]$peerMeasurement
            programExists=(Test-Path -LiteralPath $program -PathType Leaf);extraArgumentCount=$extra.Count
            childExitCode=$null;resultExists=$false;logBytes=0}
        try {
            & pwsh -NoProfile -NonInteractive -File $program -ScratchParent $root `
                -PublishDirectory (Join-Path $root 'publish') -Seconds $seconds `
                -Connections $connections @extra *> (Join-Path $root 'adapter.log')
            $launch.childExitCode=$LASTEXITCODE
            $LASTEXITCODE
        } finally {
            $launch.resultExists=Test-Path -LiteralPath (Join-Path $root 'publish\result.json') -PathType Leaf
            $log=Join-Path $root 'adapter.log'
            if(Test-Path -LiteralPath $log){$launch.logBytes=(Get-Item -LiteralPath $log).Length}
            $launch|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'child-startup.json')
            if($credentialFile -and (Test-Path -LiteralPath $credentialFile)){Remove-Item -LiteralPath $credentialFile -ErrorAction Stop}
        }
    } -ArgumentList $guestRoot,$Seconds,$Connections,([bool]$ProfileCpu),([bool]$SynDrop),([bool]$PeerMeasurement),([bool]$ManagedGc),$ManagedGcPayloadBytes,([bool]$ManagedGcPeerRecovery),([bool]$ManagedGcIsolatedData),$ManagedGcRecoveryMilliseconds,$ManagedGcProcessRole,$ManagedGcHeapLayout,([bool]$ManagedGcRouteRefresh),$ManagedGcRouteVariant,$ManagedGcReceiveBudgetBytes,$ManagedGcCacheRetirePaths,([bool]$ManagedGcWprProbes),([bool]$ManagedGcPeerPressure),$fixtureAlias,$fixtureGuid,([bool]$ManagedGcSpinLocks),$dataAlias,$dataGuid,$Credential
    $startup=Invoke-Command -Session $session -ErrorAction Stop -ScriptBlock {
        param($root)
        Get-Content -LiteralPath (Join-Path $root 'child-startup.json') -Raw|ConvertFrom-Json|
            Select-Object managedGc,peerMeasurement,programExists,extraArgumentCount,childExitCode,resultExists,logBytes
    } -ArgumentList $guestRoot |
        Select-Object managedGc,peerMeasurement,programExists,extraArgumentCount,childExitCode,resultExists,logBytes
    $phase='guest-result'
    $remoteResult=Join-Path $guestRoot 'publish\result.json'
    Copy-Item -LiteralPath $remoteResult -Destination (Join-Path $PublishDirectory 'result.json') -FromSession $session -ErrorAction Stop
    if ($ProfileCpu) {
        foreach ($file in @('cpu-idle.json','cpu-load.json','cpu-after-gc.json','cpu-after-recovery.json','clr-events.json','cpu-progress.json','tcp-state.json','tcp-events.json','lock-evidence.json')) {
            $remoteFile=Join-Path $guestRoot "publish\$file"
            if (Invoke-Command -Session $session -ScriptBlock {param($p) Test-Path -LiteralPath $p -PathType Leaf} -ArgumentList $remoteFile) {
                Copy-Item -LiteralPath $remoteFile -Destination (Join-Path $PublishDirectory $file) `
                    -FromSession $session -ErrorAction Stop
            }
        }
    }
    $result=Get-Content -LiteralPath (Join-Path $PublishDirectory 'result.json') -Raw | ConvertFrom-Json
    $expected=if($SynDrop){'observed-syn-failures'}else{'collected'}
    if ($exit -ne 0 -or $result.outcome -ne $expected) { throw 'Guest experiment or cleanup did not succeed.' }
    $success=$true
} catch {
    if (-not (Test-Path -LiteralPath (Join-Path $PublishDirectory 'result.json'))) {
        $reason='unclassified'
        if($_.Exception.Message -match 'Guest has an active Actions worker or CTS process|Client guest is busy|Peer guest is busy|Guest became busy'){
            $reason='guest-busy'
        }elseif($_.Exception.Message -match 'Owned client GC resources require restoration|Owned peer GC resources require restoration'){
            $reason='owned-resources-require-restoration'
        }elseif($_.Exception.Message -match 'running generation-2 test VM'){
            $reason='unsupported-hot-add-topology'
        }elseif($_.Exception.Message -match 'disconnected new interface unexpectedly'){
            $reason='unexpected-disposable-interface-ipv4'
        }elseif($_.Exception.Message -match 'bootstrap address is already in use'){
            $reason='disposable-bootstrap-in-use'
        }
        [ordered]@{schema=1;workload='tcp-churn';outcome='failed';phase=$phase
            failureType=$_.Exception.GetType().FullName;failureCode=$_.Exception.HResult
            failureReason=$reason
            startup=$startup;conclusion='no-measurement'} |
            ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $PublishDirectory 'result.json') -Encoding utf8
    }
} finally {
    if($rssAttempted -and $null -ne $session){
        try{
            if($null -eq $rssEvidence){
                $rssEvidence=Invoke-Command -Session $session -ErrorAction Stop -ScriptBlock {
                    param($root)
                    $path=Join-Path $root 'rss-prepared.json'
                    if(Test-Path -LiteralPath $path){Get-Content -LiteralPath $path -Raw|ConvertFrom-Json}
                } -ArgumentList $guestRoot|Select-Object schema,action,verified,phase,failureType,failureCode,sourceLine,
                    requestedProcessors,actualQueues,actualMaxProcessors,actualProcessorArrayCount,diagnosticFailureType
            }
            $rssRestored=Invoke-Command -Session $session -ErrorAction Stop -ScriptBlock {
                param($root)
                $state=Join-Path $root 'rss-original.clixml'
                if(Test-Path -LiteralPath $state){
                    & (Join-Path $root 'experiment\adapters\Set-ScopedRss.ps1') -Action restore `
                        -StateFile $state -ReportFile (Join-Path $root 'rss-restored.json')
                    Get-Content -LiteralPath (Join-Path $root 'rss-restored.json') -Raw|ConvertFrom-Json
                }
            } -ArgumentList $guestRoot|Select-Object schema,action,verified,adapterRestarted,queues,maxProcessors,
                activeProcessorArrayCount,originalQueues,originalMaxProcessors,originalAddressesAndDefaultsPreserved,carriesDefaultRoute
            $resultFile=Join-Path $PublishDirectory 'result.json'
            if($null -ne $rssRestored -and (Test-Path -LiteralPath $resultFile)){
                $published=Get-Content -LiteralPath $resultFile -Raw|ConvertFrom-Json
                $published|Add-Member NoteProperty scopedRss ([pscustomobject]@{requested=$ManagedGcRssProcessors;prepared=$rssEvidence;restored=$rssRestored}) -Force
                $published|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $resultFile
            }
        }catch{
            $success=$false
            @{schema=1;outcome='failed';phase='guest-scoped-rss-restore';cleanupVerified=$false
                failureType=$_.Exception.GetType().FullName;conclusion='no-accepted-measurement'}|
                ConvertTo-Json|Set-Content -LiteralPath (Join-Path $PublishDirectory 'result.json')
        }
    }
    if($ManagedGcUnusedInterface -and (Test-Path -LiteralPath $vmFixtureState)){
        try{
            Remove-TcpChurnVmPathFixture -StateFile $vmFixtureState
            $resultFile=Join-Path $PublishDirectory 'result.json'
            if(Test-Path -LiteralPath $resultFile){
                $published=Get-Content -LiteralPath $resultFile -Raw|ConvertFrom-Json
                $published|Add-Member NoteProperty ownedVmPathInterfaceRemoved $true -Force
                $published|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $resultFile
            }
        }catch{
            $success=$false
            @{schema=1;outcome='failed';phase='owned-vm-path-interface-cleanup';cleanupVerified=$false
                failureType=$_.Exception.GetType().FullName;conclusion='no-accepted-measurement'}|
                ConvertTo-Json|Set-Content -LiteralPath (Join-Path $PublishDirectory 'result.json')
        }
    }
    if($ManagedGcOwnedDataInterface -and (Test-Path -LiteralPath $dataFixtureState)){
        try{
            Remove-TcpChurnVmPathFixture -StateFile $dataFixtureState
            $resultFile=Join-Path $PublishDirectory 'result.json'
            if(Test-Path -LiteralPath $resultFile){
                $published=Get-Content -LiteralPath $resultFile -Raw|ConvertFrom-Json
                $published|Add-Member NoteProperty ownedVmDataInterfaceRemoved $true -Force
                if($null -ne $dataFixture){$published|Add-Member NoteProperty ownedDataRss $dataFixture.Rss -Force}
                elseif($null -ne $session){
                    $dataRssFailure=Invoke-Command -Session $session -ErrorAction Stop -ScriptBlock {
                        param($root)
                        $path=Join-Path $root 'data-rss-prepared.json'
                        if(Test-Path -LiteralPath $path){Get-Content -LiteralPath $path -Raw|ConvertFrom-Json}
                    } -ArgumentList $guestRoot|Select-Object schema,action,verified,phase,failureType,failureCode,sourceLine,
                        requestedProcessors,actualQueues,actualMaxProcessors,actualProcessorArrayCount
                    if($null -ne $dataRssFailure){$published|Add-Member NoteProperty ownedDataRss $dataRssFailure -Force}
                }
                $published|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $resultFile
            }
        }catch{
            $success=$false
            @{schema=1;outcome='failed';phase='owned-vm-data-interface-cleanup';cleanupVerified=$false
                failureType=$_.Exception.GetType().FullName;conclusion='no-accepted-measurement'}|
                ConvertTo-Json|Set-Content -LiteralPath (Join-Path $PublishDirectory 'result.json')
        }
    }
    if ($null -ne $session) { Remove-PSSession $session -ErrorAction Stop }
}
if (-not $success) { throw "Dedicated guest experiment failed at $phase; inspect the numeric result and owned cleanup status." }
Write-Output 'Real netperf guest traffic and owned fixture cleanup completed.'
