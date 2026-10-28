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
    [ValidateSet(0,1024,8192,24576)][int]$ManagedGcCacheRetirePaths=0
)
$ErrorActionPreference='Stop'
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
    -not $ManagedGcIsolatedData -or $ManagedGcPeerRecovery -or $ManagedGcRouteRefresh)){
    throw 'Cache retirement requires isolated receiver-GC mode without another fault or route control.'
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
try {
    if ((Get-VM -Name $VmName -ErrorAction Stop).State -ne 'Running') {
        throw 'The documented guest must already be running; this adapter does not reset other workloads.'
    }
    $session=New-PSSession -VMName $VmName -Credential $Credential -ErrorAction Stop
    if ($ProbePeer) {
        $phase='peer-connectivity'
        $peerResult=Invoke-Command -Session $session -ErrorAction Stop -ScriptBlock {
            param($credential)
            if (@(Get-Process -Name 'Runner.Worker','ctsTraffic','ArrivalTcp','CpuSamples' -ErrorAction Ignore).Count) { throw 'Client guest is busy.' }
            $clientAliases=@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop|Where-Object{$_.IPAddress -match '^198\.19\.240\.[1-6]$' -or $_.IPAddress -eq '198.19.0.1'}).Count
            $clientRules=@(Get-NetFirewallRule -PolicyStore ActiveStore -ErrorAction Stop|Where-Object{$_.Name -like 'ManagedGcPeer-*' -or $_.Name -like 'ManagedGcReceiver-*'}).Count
            $clientStatic=@(Get-NetNeighbor -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|
                Where-Object{$_.IPAddress -match '^198\.19\.240\.[1-6]$' -and [string]$_.State -eq 'Permanent'}).Count
            $clientRoutes=@(Get-NetRoute -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|Where-Object DestinationPrefix -in @('198.19.240.6/32','198.19.0.0/17')).Count
            if($clientAliases -or $clientRules -or $clientStatic -or $clientRoutes){throw 'Owned client GC resources require restoration before further tests.'}
            $clientCpus=(Get-CimInstance Win32_Processor|Measure-Object NumberOfLogicalProcessors -Sum).Sum
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
                    clientOwnedControlRoutes=$clientRoutes;peerOwnedControlRoutes=$peerState.routes;conclusion='connectivity-and-owned-resource-check'}
            } finally { Remove-PSSession $peer -ErrorAction Stop }
        } -ArgumentList $Credential
        $peerResult|Select-Object schema,peerConnected,clientLogicalProcessors,peerLogicalProcessors,clientOwnedAliases,peerOwnedAliases,
            clientOwnedRules,peerOwnedRules,clientOwnedStaticPeers,peerOwnedStaticPeers,clientOwnedControlRoutes,peerOwnedControlRoutes,
            clientTempFreeMiB,peerTempFreeMiB,conclusion|ConvertTo-Json |
            Set-Content -LiteralPath (Join-Path $PublishDirectory 'peer-check.json') -Encoding utf8
        return
    }
    $phase='guest-idle-check'
    $guestRoot=Invoke-Command -Session $session -ErrorAction Stop -ScriptBlock {
        if (@(Get-Process -Name 'Runner.Worker','ctsTraffic' -ErrorAction Ignore).Count) {
            throw 'Guest has an active Actions worker or CTS process.'
        }
        $root=Join-Path $env:TEMP ('netperf-churn-'+[guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -ErrorAction Stop | Out-Null
        $root
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
    if($ManagedGc){$adapterFiles+=@('Invoke-ManagedGcPeerDiagnostic.ps1','Invoke-ManagedGcGuestEntry.ps1','Invoke-ScopedNeighborPulse.ps1','TcpRecoveryEvidence.psm1','Set-ScopedDataAddresses.ps1','GcReceiverTraffic.psm1','Invoke-ScopedPathRefresh.ps1','Invoke-ScopedPathRetirement.ps1')}
    foreach ($file in $adapterFiles) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination (Join-Path $remoteRoot "adapters\$file") -ToSession $session -ErrorAction Stop
    }
    $phase='guest-traffic'
    $exit=Invoke-Command -Session $session -ErrorAction Stop -ScriptBlock {
        param($root,$seconds,$connections,$profile,$synDrop,$peerMeasurement,$managedGc,$managedGcPayloadBytes,$peerRecovery,$isolatedData,$recoveryMilliseconds,$gcProcessRole,$heapLayout,$routeRefresh,$routeVariant,$receiveBudgetBytes,$cacheRetirePaths,$credential)
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
    } -ArgumentList $guestRoot,$Seconds,$Connections,([bool]$ProfileCpu),([bool]$SynDrop),([bool]$PeerMeasurement),([bool]$ManagedGc),$ManagedGcPayloadBytes,([bool]$ManagedGcPeerRecovery),([bool]$ManagedGcIsolatedData),$ManagedGcRecoveryMilliseconds,$ManagedGcProcessRole,$ManagedGcHeapLayout,([bool]$ManagedGcRouteRefresh),$ManagedGcRouteVariant,$ManagedGcReceiveBudgetBytes,$ManagedGcCacheRetirePaths,$Credential
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
        }
        [ordered]@{schema=1;workload='tcp-churn';outcome='failed';phase=$phase
            failureType=$_.Exception.GetType().FullName;failureCode=$_.Exception.HResult
            failureReason=$reason
            startup=$startup;conclusion='no-measurement'} |
            ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $PublishDirectory 'result.json') -Encoding utf8
    }
} finally {
    if ($null -ne $session) { Remove-PSSession $session -ErrorAction Stop }
}
if (-not $success) { throw "Dedicated guest experiment failed at $phase; no host/runner configuration was changed." }
Write-Output 'Real netperf guest traffic and owned fixture cleanup completed.'
