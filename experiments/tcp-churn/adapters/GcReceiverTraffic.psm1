# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'WindowsCts.psm1')
function Start-GcReceiver {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)
    $rule='ManagedGcReceiver-'+[guid]::NewGuid().ToString('N')
    $null=New-NetFirewallRule -Name $rule -DisplayName $rule -Direction Inbound -Action Allow `
        -Protocol TCP -LocalPort $State.Port -LocalAddress $State.ServerAddress -RemoteAddress $State.PeerAddress,$State.ServerAddress
    $State.Rule=$rule
    $State.Receiver=Start-TcpChurnCollector -Program $State.Executable -Arguments @(
        $State.PeerAddress,$State.ServerAddress,[string]$State.Port,[string]$State.Count,[string]$State.Rate,
        [string]$State.Payload,$State.ServerOutput,'server',[string]$State.Payload,'14529',
        [string]$State.Connections,'nodelay',("gc:{0}:2048" -f $State.HeapMiB)
    ) -Directory $State.Directory -LogPrefix (Join-Path $State.Directory 'gc-receiver')
}
function Invoke-GcReceiverTraffic {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)
    $clock=[Diagnostics.Stopwatch]::StartNew()
    Invoke-Command -Session $State.Peer -ScriptBlock {
        param($root,$source,$target,$port,$count,$rate,$payload,$concurrency)
        $output=Join-Path $root 'client.json'
        $global:OwnedManagedGcPeer.Process=Start-TcpChurnCollector -Program (Join-Path $root 'ArrivalTcp.exe') -Arguments @(
            $source,$target,[string]$port,[string]$count,[string]$rate,[string]$payload,
            $output,'client',[string]$payload,'23521',[string]$concurrency,'nodelay','dispatch:pool'
        ) -Directory $root -LogPrefix (Join-Path $root 'receiver-remote-client')
    } -ArgumentList $State.PeerRoot,$State.PeerAddress,$State.ServerAddress,$State.Port,($State.Count/2),([int][Math]::Ceiling($State.Rate/2.0)),$State.Payload,$State.Connections
    $localOutput=Join-Path $State.Directory 'receiver-local-client.json'
    $State.LocalClient=Start-TcpChurnCollector -Program $State.Executable -Arguments @(
        $State.ServerAddress,$State.ServerAddress,[string]$State.Port,[string]($State.Count/2),
        [string]([int][Math]::Ceiling($State.Rate/2.0)),[string]$State.Payload,$localOutput,
        'client',[string]$State.Payload,'14529',[string]$State.Connections,'nodelay','dispatch:pool'
    ) -Directory $State.Directory -LogPrefix (Join-Path $State.Directory 'receiver-local-client')
    if(-not $State.LocalClient.Process.WaitForExit(180000) -or $State.LocalClient.Process.ExitCode -ne 0){
        throw 'The independent local producer did not complete successfully.'
    }
    $remote=Invoke-Command -Session $State.Peer -ScriptBlock {
        $child=$global:OwnedManagedGcPeer.Process
        if(-not $child.Process.WaitForExit(180000) -or $child.Process.ExitCode -ne 0){
            throw 'The independent remote producer did not complete successfully.'
        }
        Get-Content (Join-Path $global:OwnedManagedGcPeer.Root 'client.json') -Raw|ConvertFrom-Json
    }
    if(-not $State.Receiver.Process.WaitForExit(15000) -or $State.Receiver.Process.ExitCode -ne 0){
        throw 'The profiled GC receiver did not complete successfully.'
    }
    $clock.Stop()
    $local=Get-Content $localOutput -Raw|ConvertFrom-Json
    $server=Get-Content $State.ServerOutput -Raw|ConvertFrom-Json
    foreach($endpoint in @($local,$remote,$server)) {
        if($endpoint.outcome -ne 'collected' -or $endpoint.networkErrors -ne 0 -or $endpoint.protocolErrors -ne 0 -or $endpoint.barrier){
            throw 'A receiver-GC endpoint failed protocol verification.'
        }
    }
    if($local.connections -ne $State.Count/2 -or $remote.connections -ne $State.Count/2 -or
        $server.connections -ne $State.Count -or $server.bytesReceived -ne $local.bytesSent+$remote.bytesSent -or
        $server.bytesSent -ne $local.bytesReceived+$remote.bytesReceived -or
        -not $server.managedGc.enabled -or $server.managedGc.gen2CollectionsAfter -le $server.managedGc.gen2CollectionsBefore -or
        $server.requestDispatch -ne 'thread-pool' -or $server.peakInFlight -gt $State.Connections -or
        $local.managedGc.enabled -or $remote.managedGc.enabled -or $local.arrivalDispatch -ne 'thread-pool' -or $remote.arrivalDispatch -ne 'thread-pool' -or
        $local.targets.Count -ne 1 -or $remote.targets.Count -ne 1 -or -not $local.targets[0].loopback -or $remote.targets[0].loopback){
        throw 'Receiver-GC byte counts, real collection, independent producers or loopback classification did not verify.'
    }
    [pscustomobject]@{
        connections=$server.connections;bytesSent=$server.bytesSent;bytesReceived=$server.bytesReceived;managedGc=$server.managedGc
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
