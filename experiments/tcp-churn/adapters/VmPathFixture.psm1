# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Remove-TcpChurnVmPathFixture {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StateFile)
    $state=Import-Clixml -LiteralPath $StateFile -ErrorAction Stop
    if($state.owner -ne 'tcp-churn-path-fixture-v1' -or $state.name -notmatch '^Netperf(?:Path|Data)-[0-9a-f]{12}$'){
        throw 'The VM path-interface snapshot is not owned by this fixture.'
    }
    $vm=Get-VM -Name $state.vmName -ErrorAction Stop
    if([string]$vm.Id -ne $state.vmId){throw 'The fixture VM identity changed; refusing removal.'}
    $adapters=@(Get-VMNetworkAdapter -VMName $state.vmName -ErrorAction Stop|Where-Object Name -eq $state.name)
    if($adapters.Count -gt 1){throw 'The owned VM interface is no longer unique.'}
    if($adapters.Count){
        if([string]$adapters[0].Id -ne $state.adapterId -or $adapters[0].MacAddress -ne $state.mac){
            throw 'The VM interface identity changed; refusing removal.'
        }
        Remove-VMNetworkAdapter -VMNetworkAdapter $adapters[0] -Confirm:$false -ErrorAction Stop
    }
    if(@(Get-VMNetworkAdapter -VMName $state.vmName -ErrorAction Stop|Where-Object Name -eq $state.name).Count){
        throw 'The owned VM interface removal did not verify.'
    }
}
function New-TcpChurnVmPathFixture {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$VmName,[Parameter(Mandatory)]$Session,[Parameter(Mandatory)][string]$StateFile,
        [ValidateSet('path','data')][string]$Purpose='path',[string]$GuestRoot,[ValidateRange(1,128)][int]$RssProcessors=64)
    if(Test-Path -LiteralPath $StateFile){throw 'A fresh VM path-interface snapshot is required.'}
    $vm=Get-VM -Name $VmName -ErrorAction Stop
    $prefix=if($Purpose -eq 'data'){'NetperfData-'}else{'NetperfPath-'}
    if(@(Get-VMNetworkAdapter -VMName $VmName -ErrorAction Stop|Where-Object{$_.Name.StartsWith($prefix)}).Count){
        throw 'An existing owned VM path interface requires restoration first.'
    }
    if([string]$vm.State -ne 'Running' -or $vm.Generation -ne 2){
        throw 'The owned path interface requires a running generation-2 test VM.'
    }
    $sourceMac=Invoke-Command -Session $Session -ErrorAction Stop -ScriptBlock {
        $peer=@([Net.Dns]::GetHostAddresses('netperf-peer')|Where-Object AddressFamily -eq InterNetwork)[0].ToString()
        $route=@(Find-NetRoute -RemoteIPAddress $peer -ErrorAction Stop|Where-Object{$_.PSObject.Properties['IPAddress']})
        if($route.Count -ne 1){throw 'The peer route must identify one existing data interface.'}
        $nic=@(Get-NetAdapter -Name $route[0].InterfaceAlias -ErrorAction Stop)
        if($nic.Count -ne 1){throw 'The existing data MAC is not unique.'}
        $nic[0].MacAddress -replace '[-:]',''
    }
    $connected=@(Get-VMNetworkAdapter -VMName $VmName -ErrorAction Stop|
        Where-Object{$_.SwitchName -and ($_.MacAddress -replace '[-:]','') -eq $sourceMac})
    if($connected.Count -ne 1){throw 'The guest data MAC must match exactly one existing VM switch connection.'}
    if($Purpose -eq 'data' -and [string]::IsNullOrWhiteSpace($GuestRoot)){throw 'The disposable data interface requires its owned guest scratch root.'}
    $name=$prefix+[guid]::NewGuid().ToString('N').Substring(0,12)
    $bootstrap=if($Purpose -eq 'data'){'198.19.255.253'}else{'198.19.255.254'}
    $mac='02'+([guid]::NewGuid().ToString('N').Substring(0,10)).ToUpperInvariant()
    $created=$null;$failure=$null
    try{
        # Configure the new disconnected guest interface before connecting it, so it never requests a management DHCP lease.
        $created=Add-VMNetworkAdapter -VMName $VmName -Name $name -StaticMacAddress $mac -Passthru -ErrorAction Stop
        $state=@{owner='tcp-churn-path-fixture-v1';vmName=$VmName;vmId=[string]$vm.Id
            adapterId=[string]$created.Id;name=$name;mac=$mac}
        $state|Export-Clixml -LiteralPath $StateFile -NoClobber
        $guest=Invoke-Command -Session $Session -ErrorAction Stop -ScriptBlock {
            param($mac,$name,$bootstrap)
            $wait=[Diagnostics.Stopwatch]::StartNew()
            do{
                $adapters=@(Get-NetAdapter -ErrorAction Stop|Where-Object{($_.MacAddress -replace '[-:]','') -eq $mac})
                if($adapters.Count -gt 1){throw 'The newly owned guest MAC is not unique.'}
                if($adapters.Count -eq 1){break}
                if($wait.Elapsed.TotalSeconds -gt 20){throw 'The disconnected owned VM interface did not appear.'}
                Start-Sleep -Milliseconds 100
            }while($true)
            $adapter=$adapters[0]
            if(@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop|Where-Object InterfaceIndex -eq $adapter.ifIndex).Count){
                throw 'The disconnected new interface unexpectedly has an IPv4 configuration.'
            }
            if(@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop|Where-Object IPAddress -eq $bootstrap).Count){
                throw 'The disposable static bootstrap address is already in use.'
            }
            Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -Dhcp Disabled -ErrorAction Stop
            Rename-NetAdapter -Name $adapter.Name -NewName $name -ErrorAction Stop
            $null=New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $bootstrap -PrefixLength 32 `
                -SkipAsSource $true -PolicyStore ActiveStore -ErrorAction Stop
            [pscustomobject]@{alias=$name;guid=[string]$adapter.InterfaceGuid}
        } -ArgumentList $mac,$name,$bootstrap
        Connect-VMNetworkAdapter -VMNetworkAdapter $created -SwitchName $connected[0].SwitchName -ErrorAction Stop
        $rss=$null
        if($Purpose -eq 'data'){
            $rss=Invoke-Command -Session $Session -ErrorAction Stop -ScriptBlock {
                param($root,$alias,$guid,$processors)
                & (Join-Path $root 'experiment\adapters\Set-ScopedRss.ps1') -Action prepare -InterfaceAlias $alias `
                    -DisposableInterfaceGuid $guid -Processors $processors -StateFile (Join-Path $root 'data-rss-original.clixml') `
                    -ReportFile (Join-Path $root 'data-rss-prepared.json')
                Get-Content -LiteralPath (Join-Path $root 'data-rss-prepared.json') -Raw|ConvertFrom-Json
            } -ArgumentList $GuestRoot,$guest.alias,$guest.guid,$RssProcessors|
                Select-Object schema,action,verified,adapterRestarted,queues,maxProcessors,activeProcessorArrayCount,
                    originalQueues,originalMaxProcessors,originalAddressesAndDefaultsPreserved,carriesDefaultRoute
        }
        $state.guestGuid=$guest.guid
        $state|Export-Clixml -LiteralPath $StateFile
        [pscustomobject]@{Alias=$guest.alias;Guid=$guest.guid;Rss=$rss}
        return
    }catch{$failure=$_}
    if($null -ne $created){
        try{
            if(Test-Path -LiteralPath $StateFile){Remove-TcpChurnVmPathFixture -StateFile $StateFile}
            else{Remove-VMNetworkAdapter -VMNetworkAdapter $created -Confirm:$false -ErrorAction Stop}
        }catch{throw [AggregateException]::new('VM path-interface setup and owned rollback failed.',[Exception[]]@($failure.Exception,$_.Exception))}
    }
    throw $failure
}
Export-ModuleMember -Function New-TcpChurnVmPathFixture,Remove-TcpChurnVmPathFixture
