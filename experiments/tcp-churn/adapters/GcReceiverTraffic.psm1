# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'WindowsCts.psm1')
function Start-GcReceiver {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)
    $State.Stage='start-receiver'
    if(-not $State.ContainsKey('ResponseBytes')){$State.ResponseBytes=$State.Payload}
    if(-not $State.ContainsKey('RemoteCount')){$State.RemoteCount=$State.Count/2}
    if(-not $State.ContainsKey('RemoteSources')){$State.RemoteSources=$State.PeerAddress}
    if(-not $State.ContainsKey('ClusterPrefix')){$State.ClusterPrefix=$null}
    if(-not $State.ContainsKey('Outage')){$State.Outage=$null}
    if($State.RemoteCount -lt 1 -or $State.RemoteCount -ge $State.Count){throw 'Both remote and local producers require connections.'}
    $State.LocalCount=$State.Count-$State.RemoteCount
    $remoteAddresses=@($State.PeerAddress,$State.ServerAddress)
    if($State.ClusterPrefix){$remoteAddresses+=$State.ClusterPrefix}
    $rule='ManagedGcReceiver-'+[guid]::NewGuid().ToString('N')
    $null=New-NetFirewallRule -Name $rule -DisplayName $rule -Direction Inbound -Action Allow `
        -Protocol TCP -LocalPort $State.Port -LocalAddress $State.ServerAddress -RemoteAddress $remoteAddresses
    $State.Rule=$rule
    $gcDescriptor="gc:{0}:2048:{1}" -f $State.HeapMiB,$State.HeapLayout
    if($State.ReceiveBudgetBytes){$gcDescriptor+=':'+$State.ReceiveBudgetBytes}
    if(-not $State.ContainsKey('ExchangesPerConnection')){$State.ExchangesPerConnection=1}
    if(-not $State.ContainsKey('FramedNagle')){$State.FramedNagle=$false}
    if(-not $State.ContainsKey('CoreClr')){$State.CoreClr=$false}
    if(-not $State.ContainsKey('IdleKeepalive')){$State.IdleKeepalive=$false}
    if(-not $State.ContainsKey('ServiceWait')){$State.ServiceWait=$false}
    if(-not $State.ContainsKey('PipelinedServiceWait')){$State.PipelinedServiceWait=$false}
    if(-not $State.ContainsKey('GcReadinessFile')){$State.GcReadinessFile=$null}
    $pacing=if($State.FramedNagle){'nagle'}else{'nodelay'}
    $arguments=@(
        $State.PeerAddress,$State.ServerAddress,[string]$State.Port,[string]$State.Count,[string]$State.Rate,
        [string]$State.Payload,$State.ServerOutput,'server',[string]$State.ResponseBytes,'14529',
        [string]$State.Connections,$pacing,$gcDescriptor
    )
    if($State.ServiceWait){$arguments+=$(if($State.PipelinedServiceWait){'servicewait64:pipelined'}else{'servicewait64'})}
    elseif($State.ExchangesPerConnection -eq 64){$arguments+=$(if($State.FramedNagle){'exchanges:64:framed'}else{'exchanges:64'})}
    elseif($State.IdleKeepalive){$arguments+='idlekeepalive'}
    if($State.GcReadinessFile){$arguments+=$State.GcReadinessFile}
    $State.Receiver=Start-TcpChurnCollector -Program $State.Executable -Arguments $arguments `
        -Directory $State.Directory -LogPrefix (Join-Path $State.Directory 'gc-receiver') -CoreClr:([bool]$State.CoreClr)
}
function Start-GcReceiverTraffic {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)
    $clock=[Diagnostics.Stopwatch]::StartNew()
    if($State.Outage){
        $State.Stage='start-peer-outage'
        Invoke-Command -Session $State.Peer -ScriptBlock {
            param($root,$addresses,$delay,$duration)
            $global:OwnedManagedGcPeer.OutageStop=Join-Path $root 'outage.stop'
            $global:OwnedManagedGcPeer.OutageReport=Join-Path $root 'outage.json'
            $global:OwnedManagedGcPeer.OutageRule='NetperfClusterOutage-'+[guid]::NewGuid().ToString('N')
            $global:OwnedManagedGcPeer.Outage=Start-TcpChurnCollector -Program (Get-Command pwsh -CommandType Application -ErrorAction Stop).Source `
                -Arguments @('-NoProfile','-NonInteractive','-File',(Join-Path $root 'Invoke-ScopedPeerOutage.ps1'),
                    '-Addresses',$addresses,'-DelayMilliseconds',[string]$delay,'-DurationMilliseconds',[string]$duration,
                    '-ReadyFile',(Join-Path $root 'outage.ready'),'-StopFile',$global:OwnedManagedGcPeer.OutageStop,
                    '-ReportFile',$global:OwnedManagedGcPeer.OutageReport,'-RuleName',$global:OwnedManagedGcPeer.OutageRule) `
                -Directory $root -LogPrefix (Join-Path $root 'outage-agent')
            $ready=[Diagnostics.Stopwatch]::StartNew()
            while(-not(Test-Path -LiteralPath (Join-Path $root 'outage.ready'))){
                if($global:OwnedManagedGcPeer.Outage.Process.HasExited -or $ready.Elapsed.TotalSeconds -gt 30){
                    throw 'The bounded peer outage agent did not become ready.'
                }
                Start-Sleep -Milliseconds 20
            }
        } -ArgumentList $State.PeerRoot,$State.Outage.Addresses,$State.Outage.DelayMilliseconds,$State.Outage.DurationMilliseconds
    }
    $State.Stage='start-remote-producer'
    Invoke-Command -Session $State.Peer -ScriptBlock {
        param($root,$source,$target,$port,$count,$rate,$payload,$responseBytes,$concurrency,$peerPressure,$exchanges,$framedNagle,$coreClr,$idleKeepalive,$serviceWait,$pipelinedServiceWait)
        $output=Join-Path $root 'client.json'
        $arguments=@(
            $source,$target,[string]$port,[string]$count,[string]$rate,[string]$payload,
            $output,'client',[string]$responseBytes,'23521',[string]$concurrency,$(if($framedNagle){'nagle'}else{'nodelay'}),'dispatch:pool'
        )
        if($serviceWait){$arguments+=$(if($pipelinedServiceWait){'servicewait64:pipelined'}else{'servicewait64'})}
        elseif($exchanges -eq 64){$arguments+=$(if($framedNagle){'exchanges:64:framed'}else{'exchanges:64'})}
        elseif($idleKeepalive){$arguments+='idlekeepalive'}
        $global:OwnedManagedGcPeer.Process=Start-TcpChurnCollector -Program (Join-Path $root 'ArrivalTcp.exe') `
            -Arguments $arguments -Directory $root -LogPrefix (Join-Path $root 'receiver-remote-client') -CoreClr:([bool]$coreClr)
        if($peerPressure){
            $global:OwnedManagedGcPeer.PressureRate=2048
            $global:OwnedManagedGcPeer.PressureClient=Start-TcpChurnCollector -Program (Join-Path $root 'ArrivalTcp.exe') -Arguments @(
                '127.0.0.1','127.0.0.2','20301','4096',[string]$global:OwnedManagedGcPeer.PressureRate,'1048576',(Join-Path $root 'pressure-client.json'),
                'client','1048576','34711','256','nodelay','dispatch:pool'
            ) -Directory $root -LogPrefix (Join-Path $root 'pressure-client')
        }
    } -ArgumentList $State.PeerRoot,$State.RemoteSources,$State.ServerAddress,$State.Port,$State.RemoteCount,([int][Math]::Ceiling($State.Rate*$State.RemoteCount/$State.Count)),$State.Payload,$State.ResponseBytes,$State.Connections,([bool]$State.PeerGcPressure),$State.ExchangesPerConnection,([bool]$State.FramedNagle),([bool]$State.CoreClr),([bool]$State.IdleKeepalive),([bool]$State.ServiceWait),([bool]$State.PipelinedServiceWait)
    $localOutput=Join-Path $State.Directory 'receiver-local-client.json'
    $State.Stage='start-local-producer'
    $arguments=@(
        $State.ServerAddress,$State.ServerAddress,[string]$State.Port,[string]$State.LocalCount,
        [string]([int][Math]::Ceiling($State.Rate*$State.LocalCount/$State.Count)),[string]$State.Payload,$localOutput,
        'client',[string]$State.ResponseBytes,'14529',[string]$State.Connections,$(if($State.FramedNagle){'nagle'}else{'nodelay'}),'dispatch:pool'
    )
    if($State.ServiceWait){$arguments+=$(if($State.PipelinedServiceWait){'servicewait64:pipelined'}else{'servicewait64'})}
    elseif($State.ExchangesPerConnection -eq 64){$arguments+=$(if($State.FramedNagle){'exchanges:64:framed'}else{'exchanges:64'})}
    elseif($State.IdleKeepalive){$arguments+='idlekeepalive'}
    $State.LocalClient=Start-TcpChurnCollector -Program $State.Executable -Arguments $arguments `
        -Directory $State.Directory -LogPrefix (Join-Path $State.Directory 'receiver-local-client') -CoreClr:([bool]$State.CoreClr)
    $State.TrafficClock=$clock
    $State.LocalOutput=$localOutput
}
function Complete-GcReceiverTraffic {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)
    $clock=$State.TrafficClock
    $localOutput=$State.LocalOutput
    $State.Stage='wait-local-producer'
    if(-not $State.LocalClient.Process.WaitForExit(180000) -or $State.LocalClient.Process.ExitCode -ne 0){
        throw 'The independent local producer did not complete successfully.'
    }
    $State.Stage='wait-remote-producer'
    $remoteBundle=Invoke-Command -Session $State.Peer -ScriptBlock {
        param($peerPressure)
        $child=$global:OwnedManagedGcPeer.Process
        if(-not $child.Process.WaitForExit(180000) -or $child.Process.ExitCode -ne 0){
            throw 'The independent remote producer did not complete successfully.'
        }
        $data=Get-Content (Join-Path $global:OwnedManagedGcPeer.Root 'client.json') -Raw|ConvertFrom-Json
        $outage=$null
        if($global:OwnedManagedGcPeer.ContainsKey('Outage') -and $null -ne $global:OwnedManagedGcPeer.Outage){
            [IO.File]::WriteAllText($global:OwnedManagedGcPeer.OutageStop,'stop')
            if(-not $global:OwnedManagedGcPeer.Outage.Process.WaitForExit(60000) -or
                $global:OwnedManagedGcPeer.Outage.Process.ExitCode -ne 0){
                throw 'The bounded peer outage agent did not complete and restore its rule.'
            }
            $outage=Get-Content -LiteralPath $global:OwnedManagedGcPeer.OutageReport -Raw|ConvertFrom-Json
        }
        $pressure=$null
        if($peerPressure){
            foreach($child in @($global:OwnedManagedGcPeer.PressureClient,$global:OwnedManagedGcPeer.PressureServer)){
                if(-not $child.Process.WaitForExit(30000) -or $child.Process.ExitCode -ne 0){
                    throw 'The independent companion GC workload did not complete successfully.'
                }
            }
            $sender=Get-Content (Join-Path $global:OwnedManagedGcPeer.Root 'pressure-client.json') -Raw|ConvertFrom-Json
            $receiver=Get-Content (Join-Path $global:OwnedManagedGcPeer.Root 'pressure-server.json') -Raw|ConvertFrom-Json
            foreach($endpoint in @($sender,$receiver)){
                if($endpoint.outcome -ne 'collected' -or $endpoint.connections -ne 4096 -or
                    $endpoint.networkErrors -ne 0 -or $endpoint.protocolErrors -ne 0 -or $endpoint.barrier -ne $false -or
                    $endpoint.bytesSent -ne 4294967296 -or $endpoint.bytesReceived -ne 4294967296){
                    throw 'The companion loopback GC workload failed byte or barrier verification.'
                }
            }
            if(-not $receiver.managedGc.enabled -or
                $receiver.managedGc.gen2CollectionsAfter -le $receiver.managedGc.gen2CollectionsBefore){
                throw 'The companion process did not perform a real generation-2 collection.'
            }
            $pressure=[pscustomobject]@{connections=4096;bytesPerDirection=4294967296;networkScope='peer-loopback-only'
                offeredArrivalRate=$global:OwnedManagedGcPeer.PressureRate;managedGc=$receiver.managedGc;barrier=$false}
        }
        [pscustomobject]@{Data=$data;Pressure=$pressure;Outage=$outage}
    } -ArgumentList ([bool]$State.PeerGcPressure)
    $remote=$remoteBundle.Data
    if($State.Outage -and ($null -eq $remoteBundle.Outage -or $remoteBundle.Outage.outcome -ne 'completed' -or
        -not $remoteBundle.Outage.applied -or -not $remoteBundle.Outage.removed -or
        $remoteBundle.Outage.affectedAddresses -ne @($State.Outage.Addresses.Split(',')).Count)){
        throw 'The requested partial outage did not apply within the workload and restore.'
    }
    $State.OutageReport=$remoteBundle.Outage
    $State.Stage='wait-receiver'
    if(-not $State.Receiver.Process.WaitForExit(15000) -or $State.Receiver.Process.ExitCode -ne 0){
        throw 'The profiled GC receiver did not complete successfully.'
    }
    $clock.Stop()
    $local=Get-Content $localOutput -Raw|ConvertFrom-Json
    $server=Get-Content $State.ServerOutput -Raw|ConvertFrom-Json
    $State.Stage='verify-endpoints'
    foreach($endpoint in @($local,$remote,$server)) {
        if($endpoint.outcome -ne 'collected' -or $endpoint.exchangesPerConnection -ne $State.ExchangesPerConnection -or
            $endpoint.framedWrites -ne [bool]$State.FramedNagle -or $endpoint.noDelay -ne (-not [bool]$State.FramedNagle) -or
            $endpoint.managedCoreLibrary -ne $(if($State.CoreClr){'System.Private.CoreLib'}else{'mscorlib'}) -or
            [string]::IsNullOrWhiteSpace([string]$endpoint.managedRuntimeVersion) -or
            $endpoint.idleKeepalive -ne [bool]$State.IdleKeepalive -or
            $endpoint.keepaliveConfiguredSockets -ne $(if($State.IdleKeepalive){$endpoint.connections}else{0}) -or
            $endpoint.serviceWait -ne [bool]$State.ServiceWait -or
            $endpoint.serviceWaitsCompleted -ne $(if($State.ServiceWait -and $endpoint.role -eq 'server'){[long]$endpoint.connections*$State.ExchangesPerConnection}else{0}) -or
            $endpoint.serviceRequestPipelining -ne [bool]$State.PipelinedServiceWait -or
            $endpoint.clientPacingWaitsCompleted -ne $(if($State.PipelinedServiceWait -and $endpoint.role -eq 'client'){[long]$endpoint.connections*($State.ExchangesPerConnection-1)}else{0}) -or
            $endpoint.clientPacingMinimumMilliseconds -ne $(if($State.PipelinedServiceWait){250}else{0}) -or
            $endpoint.clientPacingMaximumMilliseconds -ne $(if($State.PipelinedServiceWait){750}else{0}) -or
            $endpoint.maximumPerConnectionReadBufferBytes -ne [Math]::Min($(if($endpoint.role -eq 'server'){$State.Payload}else{$State.ResponseBytes}),65536) -or
            $endpoint.networkErrors -ne 0 -or $endpoint.protocolErrors -ne 0 -or $endpoint.barrier){
            throw 'A receiver-GC endpoint failed protocol verification.'
        }
    }
    $State.Stage='verify-receiver-coverage'
    if($local.connections -ne $State.LocalCount -or $remote.connections -ne $State.RemoteCount -or
        $server.connections -ne $State.Count -or $server.bytesReceived -ne ([long]$State.Count*$State.Payload*$State.ExchangesPerConnection) -or
        $server.bytesSent -ne ([long]$State.Count*$State.ResponseBytes*$State.ExchangesPerConnection) -or
        $server.bytesReceived -ne $local.bytesSent+$remote.bytesSent -or
        $server.bytesSent -ne $local.bytesReceived+$remote.bytesReceived -or
        -not $server.managedGc.enabled -or $server.managedGc.gen2CollectionsAfter -le $server.managedGc.gen2CollectionsBefore -or
        -not $server.managedGc.serverGc -or $server.managedGc.heapMiB -ne $State.HeapMiB -or
        $server.managedGc.readinessGateRequired -ne [bool]$State.GcReadinessFile -or
        $server.managedGc.readinessGateSatisfied -ne [bool]$State.GcReadinessFile -or
        $server.managedGc.heapLayout -ne $State.HeapLayout -or $server.managedGc.preparedManagedHeapBytes -le 0 -or
        $server.managedGc.preparedGraphNodeCount -ne $(if($State.HeapLayout -eq 'graph'){
            ([long][Math]::Floor(([long]$State.HeapMiB*1024*1024)/40))-band -2L
        }else{0}) -or
        ($State.HeapMiB -gt 1024 -and $server.managedGc.largeHeapFreePhysicalBytesBeforePreparation -lt ([long]$State.HeapMiB*4MB)) -or
        $server.requestDispatch -ne 'thread-pool' -or $server.peakInFlight -gt $State.Connections -or
        $server.managedGc.configuredReceiveBudgetBytes -ne $State.ReceiveBudgetBytes -or
        $server.managedGc.maximumPostedReadBytes -ne $State.ReceiveBudgetBytes -or
        ($State.ReceiveBudgetBytes -and ($server.managedGc.observedMaximumPostedReadBytes -lt 1 -or
            $server.managedGc.observedMaximumPostedReadBytes -gt $State.ReceiveBudgetBytes)) -or
        $local.managedGc.enabled -or $remote.managedGc.enabled -or $local.arrivalDispatch -ne 'thread-pool' -or $remote.arrivalDispatch -ne 'thread-pool' -or
        $local.targets.Count -ne 1 -or $remote.targets.Count -ne 1 -or -not $local.targets[0].loopback -or $remote.targets[0].loopback){
        throw 'Receiver-GC byte counts, real collection, independent producers or loopback classification did not verify.'
    }
    $State.Stage='verified'
    [pscustomobject]@{
        connections=$server.connections;bytesSent=$server.bytesSent;bytesReceived=$server.bytesReceived;managedGc=$server.managedGc
        exchangesPerConnection=$server.exchangesPerConnection
        framedWrites=$server.framedWrites;noDelay=$server.noDelay
        managedCoreLibrary=$server.managedCoreLibrary;managedRuntimeVersion=$server.managedRuntimeVersion
        idleKeepalive=$server.idleKeepalive;keepaliveConfiguredSockets=$server.keepaliveConfiguredSockets
        keepaliveIdleMillisecondsRequested=$server.keepaliveIdleMillisecondsRequested
        keepaliveIntervalMillisecondsRequested=$server.keepaliveIntervalMillisecondsRequested
        idleHoldMinimumMilliseconds=$local.idleHoldMinimumMilliseconds;idleHoldMaximumMilliseconds=$local.idleHoldMaximumMilliseconds
        serviceWait=$server.serviceWait;serviceWaitsCompleted=$server.serviceWaitsCompleted
        serviceWaitMinimumMilliseconds=$server.serviceWaitMinimumMilliseconds;serviceWaitMaximumMilliseconds=$server.serviceWaitMaximumMilliseconds
        serviceRequestPipelining=$server.serviceRequestPipelining
        clientPacingWaitsCompleted=($local.clientPacingWaitsCompleted+$remote.clientPacingWaitsCompleted)
        clientPacingMinimumMilliseconds=$server.clientPacingMinimumMilliseconds;clientPacingMaximumMilliseconds=$server.clientPacingMaximumMilliseconds
        maximumPerConnectionReadBufferBytes=$server.maximumPerConnectionReadBufferBytes
        peerGcPressure=$remoteBundle.Pressure
        responseBytesPerExchange=$State.ResponseBytes
        remoteSourceAddresses=@($State.RemoteSources.Split(',')).Count
        partialOutage=$remoteBundle.Outage
        arrivalRate=(2*[Math]::Ceiling($State.Rate/2.0));arrivalDispatch='independent-client-processes';peakInFlight=$server.peakInFlight
        maxLaunchLagMilliseconds=[Math]::Max($local.maxLaunchLagMilliseconds,$remote.maxLaunchLagMilliseconds)
        meanDispatchQueueMilliseconds=($local.meanDispatchQueueMilliseconds+$remote.meanDispatchQueueMilliseconds)/2
        maxDispatchQueueMilliseconds=[Math]::Max($local.maxDispatchQueueMilliseconds,$remote.maxDispatchQueueMilliseconds)
        launchSpanMilliseconds=[Math]::Max($local.launchSpanMilliseconds,$remote.launchSpanMilliseconds)
        milliseconds=$clock.ElapsedMilliseconds
        meanBindMilliseconds=($local.meanBindMilliseconds+$remote.meanBindMilliseconds)/2
        meanConnectMilliseconds=($local.meanConnectMilliseconds+$remote.meanConnectMilliseconds)/2
        targets=@(
            @{index=0;loopback=$false;connections=$remote.connections;requestBytes=$remote.bytesSent;responseBytes=$remote.bytesReceived},
            @{index=1;loopback=$true;connections=$local.connections;requestBytes=$local.bytesSent;responseBytes=$local.bytesReceived}
        )
    }
}
function Invoke-GcReceiverTraffic {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)
    Start-GcReceiverTraffic -State $State
    Complete-GcReceiverTraffic -State $State
}
Export-ModuleMember -Function Start-GcReceiver,Start-GcReceiverTraffic,Complete-GcReceiverTraffic,Invoke-GcReceiverTraffic
