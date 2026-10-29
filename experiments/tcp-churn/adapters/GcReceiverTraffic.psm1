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
    $rule='ManagedGcReceiver-'+[guid]::NewGuid().ToString('N')
    $null=New-NetFirewallRule -Name $rule -DisplayName $rule -Direction Inbound -Action Allow `
        -Protocol TCP -LocalPort $State.Port -LocalAddress $State.ServerAddress -RemoteAddress $State.PeerAddress,$State.ServerAddress
    $State.Rule=$rule
    $gcDescriptor="gc:{0}:2048:{1}" -f $State.HeapMiB,$State.HeapLayout
    if($State.ReceiveBudgetBytes){$gcDescriptor+=':'+$State.ReceiveBudgetBytes}
    if(-not $State.ContainsKey('ExchangesPerConnection')){$State.ExchangesPerConnection=1}
    if(-not $State.ContainsKey('FramedNagle')){$State.FramedNagle=$false}
    if(-not $State.ContainsKey('CoreClr')){$State.CoreClr=$false}
    $pacing=if($State.FramedNagle){'nagle'}else{'nodelay'}
    $arguments=@(
        $State.PeerAddress,$State.ServerAddress,[string]$State.Port,[string]$State.Count,[string]$State.Rate,
        [string]$State.Payload,$State.ServerOutput,'server',[string]$State.Payload,'14529',
        [string]$State.Connections,$pacing,$gcDescriptor
    )
    if($State.ExchangesPerConnection -eq 64){$arguments+=$(if($State.FramedNagle){'exchanges:64:framed'}else{'exchanges:64'})}
    $State.Receiver=Start-TcpChurnCollector -Program $State.Executable -Arguments $arguments `
        -Directory $State.Directory -LogPrefix (Join-Path $State.Directory 'gc-receiver') -CoreClr:([bool]$State.CoreClr)
}
function Invoke-GcReceiverTraffic {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $State.Stage='start-remote-producer'
    Invoke-Command -Session $State.Peer -ScriptBlock {
        param($root,$source,$target,$port,$count,$rate,$payload,$concurrency,$peerPressure,$exchanges,$framedNagle,$coreClr)
        $output=Join-Path $root 'client.json'
        $arguments=@(
            $source,$target,[string]$port,[string]$count,[string]$rate,[string]$payload,
            $output,'client',[string]$payload,'23521',[string]$concurrency,$(if($framedNagle){'nagle'}else{'nodelay'}),'dispatch:pool'
        )
        if($exchanges -eq 64){$arguments+=$(if($framedNagle){'exchanges:64:framed'}else{'exchanges:64'})}
        $global:OwnedManagedGcPeer.Process=Start-TcpChurnCollector -Program (Join-Path $root 'ArrivalTcp.exe') `
            -Arguments $arguments -Directory $root -LogPrefix (Join-Path $root 'receiver-remote-client') -CoreClr:([bool]$coreClr)
        if($peerPressure){
            $global:OwnedManagedGcPeer.PressureRate=2048
            $global:OwnedManagedGcPeer.PressureClient=Start-TcpChurnCollector -Program (Join-Path $root 'ArrivalTcp.exe') -Arguments @(
                '127.0.0.1','127.0.0.2','20301','4096',[string]$global:OwnedManagedGcPeer.PressureRate,'1048576',(Join-Path $root 'pressure-client.json'),
                'client','1048576','34711','256','nodelay','dispatch:pool'
            ) -Directory $root -LogPrefix (Join-Path $root 'pressure-client')
        }
    } -ArgumentList $State.PeerRoot,$State.PeerAddress,$State.ServerAddress,$State.Port,($State.Count/2),([int][Math]::Ceiling($State.Rate/2.0)),$State.Payload,$State.Connections,([bool]$State.PeerGcPressure),$State.ExchangesPerConnection,([bool]$State.FramedNagle),([bool]$State.CoreClr)
    $localOutput=Join-Path $State.Directory 'receiver-local-client.json'
    $State.Stage='start-local-producer'
    $arguments=@(
        $State.ServerAddress,$State.ServerAddress,[string]$State.Port,[string]($State.Count/2),
        [string]([int][Math]::Ceiling($State.Rate/2.0)),[string]$State.Payload,$localOutput,
        'client',[string]$State.Payload,'14529',[string]$State.Connections,$(if($State.FramedNagle){'nagle'}else{'nodelay'}),'dispatch:pool'
    )
    if($State.ExchangesPerConnection -eq 64){$arguments+=$(if($State.FramedNagle){'exchanges:64:framed'}else{'exchanges:64'})}
    $State.LocalClient=Start-TcpChurnCollector -Program $State.Executable -Arguments $arguments `
        -Directory $State.Directory -LogPrefix (Join-Path $State.Directory 'receiver-local-client') -CoreClr:([bool]$State.CoreClr)
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
        [pscustomobject]@{Data=$data;Pressure=$pressure}
    } -ArgumentList ([bool]$State.PeerGcPressure)
    $remote=$remoteBundle.Data
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
            $endpoint.maximumPerConnectionReadBufferBytes -ne [Math]::Min($State.Payload,65536) -or
            $endpoint.networkErrors -ne 0 -or $endpoint.protocolErrors -ne 0 -or $endpoint.barrier){
            throw 'A receiver-GC endpoint failed protocol verification.'
        }
    }
    $State.Stage='verify-receiver-coverage'
    if($local.connections -ne $State.Count/2 -or $remote.connections -ne $State.Count/2 -or
        $server.connections -ne $State.Count -or $server.bytesReceived -ne ([long]$State.Count*$State.Payload*$State.ExchangesPerConnection) -or
        $server.bytesSent -ne ([long]$State.Count*$State.Payload*$State.ExchangesPerConnection) -or
        $server.bytesReceived -ne $local.bytesSent+$remote.bytesSent -or
        $server.bytesSent -ne $local.bytesReceived+$remote.bytesReceived -or
        -not $server.managedGc.enabled -or $server.managedGc.gen2CollectionsAfter -le $server.managedGc.gen2CollectionsBefore -or
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
        maximumPerConnectionReadBufferBytes=$server.maximumPerConnectionReadBufferBytes
        peerGcPressure=$remoteBundle.Pressure
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
Export-ModuleMember -Function Start-GcReceiver,Invoke-GcReceiverTraffic
