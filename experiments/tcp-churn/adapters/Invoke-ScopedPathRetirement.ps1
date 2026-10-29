# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InterfaceAlias,
    [Parameter(Mandatory)][string]$DataStateFile,
    [Parameter(Mandatory)][string]$StateFile,
    [Parameter(Mandatory)][string]$ReportFile,
    [ValidateSet(1,1024,8192,24576,49152)][int]$PathCount=8192,
    [string]$ReceiverExecutable,[int]$ReceiverProcessId,
    [string]$UnusedInterfaceGuid,
    [string]$ReadyFile,[string]$BeginFile,[string]$EndFile,[string]$StopFile,
    [switch]$RestoreOnly
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
trap {
    if(-not(Test-Path -LiteralPath $ReportFile)){
        @{schema=1;scenario='owned-secondary-source-address-retirement';outcome='failed'
            phase='control-preflight';failureType=$_.Exception.GetType().FullName
            failureCode=$_.Exception.HResult;sourceLine=$_.InvocationInfo.ScriptLineNumber
            retired=$false;restored=$false}|ConvertTo-Json|Set-Content -LiteralPath $ReportFile
    }
    break
}
if(-not $RestoreOnly -and (!$ReadyFile -or !$BeginFile -or !$StopFile)){
    throw 'Path retirement requires owned lifecycle files.'
}
$source='198.19.0.1';$prefix='198.19.0.0/17'
$sources=@($source)
if($PathCount -eq 49152){$sources+='198.19.0.2'}
$adapter=@(Get-NetAdapter -Name $InterfaceAlias -ErrorAction Stop)
if($adapter.Count -ne 1){throw 'The owned data adapter must be unique.'}
$data=Import-Clixml -LiteralPath $DataStateFile -ErrorAction Stop
$detachInterface=-not [string]::IsNullOrWhiteSpace($UnusedInterfaceGuid)
if($EndFile -and -not $detachInterface){throw 'GC-completion retirement requires the owned unused interface.'}
$ownedInterface=if($detachInterface){
    $InterfaceAlias -match '^NetperfPath-[0-9a-f]{12}$' -and
        [guid]$UnusedInterfaceGuid -eq $adapter[0].InterfaceGuid -and $data.interfaceGuid -ne [string]$adapter[0].InterfaceGuid
}else{$data.interfaceGuid -eq [string]$adapter[0].InterfaceGuid}
if(-not $ownedInterface -or -not $data.originalDhcpDisabled -or
    '198.19.240.1' -notin @($data.addresses) -or
    @($data.addresses|Where-Object{$_ -notmatch '^198\.19\.240\.[1-4]$'}).Count){
    throw 'Path retirement requires owned receiver addresses and unchanged static management policy.'
}
function Read-Defaults {
    @(Get-NetRoute -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|
        Where-Object DestinationPrefix -eq '0.0.0.0/0'|
        ForEach-Object{"$($_.InterfaceIndex)/$($_.NextHop)/$($_.RouteMetric)"}|Sort-Object)
}
function Read-Addresses {
    @(Get-NetIPAddress -InterfaceIndex $adapter[0].ifIndex -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|
        ForEach-Object{"$($_.IPAddress)/$($_.PrefixLength)/$($_.SkipAsSource)"}|Sort-Object)
}
function Get-Range([string]$Cidr) {
    $parts=$Cidr.Split('/');$bits=[int]$parts[1]
    if($bits -lt 0 -or $bits -gt 32){throw 'Invalid IPv4 prefix.'}
    $bytes=[Net.IPAddress]::Parse($parts[0]).GetAddressBytes()
    if($bytes.Length -ne 4){throw 'An IPv4 prefix is required.'}
    $number=[uint64]$bytes[0]*16777216+[uint64]$bytes[1]*65536+[uint64]$bytes[2]*256+[uint64]$bytes[3]
    $size=[uint64][Math]::Pow(2,32-$bits);$first=$number-($number%$size)
    [pscustomobject]@{First=$first;Last=$first+$size-1}
}
function Read-OwnedAddress {
    @(Get-NetIPAddress -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|Where-Object{$_.IPAddress -in $sources})
}
function Restore-Control {
    param([switch]$MeasureRetirement)
    $saved=Import-Clixml -LiteralPath $StateFile -ErrorAction Stop
    $savedSources=if($saved.ContainsKey('sources')){@($saved.sources)}else{@($saved.source)}
    $savedDetach=$saved.ContainsKey('detachInterface') -and [bool]$saved.detachInterface
    if($saved.interfaceGuid -ne [string]$adapter[0].InterfaceGuid -or $saved.source -ne $source -or
        $saved.prefix -ne $prefix -or -not $saved.originalAbsent -or $savedDetach -ne $detachInterface -or
        (($savedSources|Sort-Object)-join '|') -ne (($sources|Sort-Object)-join '|')){
        throw 'The path-retirement snapshot does not match the owned control.'
    }
    if($detachInterface){
        $binding=@(Get-NetAdapterBinding -Name $InterfaceAlias -ComponentID ms_tcpip -ErrorAction Stop)
        if($binding.Count -ne 1){throw 'The owned unused-interface binding is not unique.'}
        if(-not $binding[0].Enabled){
            Enable-NetAdapterBinding -Name $InterfaceAlias -ComponentID ms_tcpip -Confirm:$false -ErrorAction Stop
        }
        $wait=[Diagnostics.Stopwatch]::StartNew()
        do{
            $currentAdapter=@(Get-NetAdapter -Name $InterfaceAlias -ErrorAction Stop)
            if($currentAdapter.Count -ne 1 -or [string]$currentAdapter[0].InterfaceGuid -ne $saved.interfaceGuid){
                throw 'The unused interface changed identity during IPv4 restoration.'
            }
            $adapter=$currentAdapter
            $ipInterfaces=@(Get-NetIPInterface -AddressFamily IPv4 -ErrorAction Stop|Where-Object InterfaceIndex -eq $adapter[0].ifIndex)
            if($ipInterfaces.Count -eq 1){break}
            if($wait.Elapsed.TotalSeconds -gt 15){throw 'The unused IPv4 interface did not return after binding restoration.'}
            Start-Sleep -Milliseconds 50
        }while($true)
        Set-NetIPInterface -InterfaceIndex $adapter[0].ifIndex -AddressFamily IPv4 -Dhcp Disabled -ErrorAction Stop
        if('198.19.255.254/32/True' -in @($saved.originalAddresses)){
            $bootstrap=@(Get-NetIPAddress -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|
                Where-Object IPAddress -eq '198.19.255.254')
            if($bootstrap.Count -eq 0){
                $null=New-NetIPAddress -InterfaceIndex $adapter[0].ifIndex -IPAddress '198.19.255.254' -PrefixLength 32 `
                    -SkipAsSource $true -PolicyStore ActiveStore -ErrorAction Stop
            }elseif($bootstrap.Count -ne 1 -or $bootstrap[0].InterfaceIndex -ne $adapter[0].ifIndex -or
                $bootstrap[0].PrefixLength -ne 32 -or -not $bootstrap[0].SkipAsSource){
                throw 'The owned static bootstrap address changed identity during restoration.'
            }
        }
    }
    $current=@(Read-OwnedAddress)
    if(@($current|Group-Object IPAddress|Where-Object Count -ne 1).Count){throw 'An owned source address is no longer unique.'}
    if($MeasureRetirement -and $current.Count -ne $sources.Count){throw 'An owned source disappeared before measured retirement.'}
    foreach($entry in $current){
        if($entry.InterfaceIndex -ne $adapter[0].ifIndex -or $entry.PrefixLength -ne 17 -or
            -not $entry.SkipAsSource){throw 'The retirement address changed ownership; refusing removal.'}
    }
    if($current.Count) {
        if($MeasureRetirement){$report.removeApiStartUtc=[DateTime]::UtcNow.ToString('o')}
        foreach($entry in $current){
            Remove-NetIPAddress -InterfaceIndex $adapter[0].ifIndex -IPAddress $entry.IPAddress -PolicyStore ActiveStore `
                -Confirm:$false -ErrorAction Stop
        }
        if($MeasureRetirement){$report.removeApiEndUtc=[DateTime]::UtcNow.ToString('o')}
    }
    $routes=@(Get-NetRoute -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop|
        Where-Object DestinationPrefix -eq $prefix)
    if(@(Read-OwnedAddress).Count -or $routes.Count -or
        (@(Read-Addresses)-join '|') -ne (@($saved.originalAddresses)-join '|') -or
        (@(Read-Defaults)-join '|') -ne (@($data.originalDefaultKeys)-join '|')){
        throw 'Source retirement, original addresses or unchanged default routes did not verify.'
    }
    $network=@(Get-NetIPInterface -InterfaceIndex $adapter[0].ifIndex -AddressFamily IPv4 -ErrorAction Stop)
    if($network.Count -ne 1 -or [string]$network[0].Dhcp -ne 'Disabled'){
        throw 'The original static IPv4 policy changed during path retirement.'
    }
}
function Read-PrefixPathCount {
    $rows=@(& "$env:SystemRoot\System32\netsh.exe" interface ipv4 show destinationcache "interface=$InterfaceAlias")
    if($LASTEXITCODE){throw 'Cannot enumerate the owned cached paths.'}
    @($rows|Where-Object{
        if($_ -match '^\s*\d+\s+198\.19\.(\d+)\.') {return [int]$Matches[1] -lt 128}
        return $false
    }).Count
}
$pathTiming=@{QueryMilliseconds=0;RowScanMilliseconds=0}
function Wait-ControlSignal([string]$File,[int]$PollMilliseconds=5) {
    $deadline=[Diagnostics.Stopwatch]::StartNew()
    if(Test-Path -LiteralPath $StopFile){throw 'Traffic stopped before the retirement signal.'}
    while(-not(Test-Path -LiteralPath $File)){
        if(Test-Path -LiteralPath $StopFile){throw 'Traffic stopped before the retirement signal.'}
        if($deadline.Elapsed.TotalSeconds -gt 60){throw 'The required real-GC signal did not reach the retirement control.'}
        Start-Sleep -Milliseconds $PollMilliseconds
    }
}
function Read-PathCount {
    [double]$query=0;[double]$scan=0
    $count=[ArrivalTcp]::CountIpv4PathsForSources($adapter[0].ifIndex,[string[]]$sources,[ref]$query,[ref]$scan)
    $pathTiming.QueryMilliseconds=$query;$pathTiming.RowScanMilliseconds=$scan
    $count
}
if($RestoreOnly){
    Restore-Control
    @{schema=1;removed=$true;defaultRoutesPreserved=$true}|ConvertTo-Json|Set-Content -LiteralPath $ReportFile
    return
}
if(Test-Path -LiteralPath $StateFile){throw 'A fresh path-retirement snapshot is required.'}
if($detachInterface){
    $binding=@(Get-NetAdapterBinding -Name $InterfaceAlias -ComponentID ms_tcpip -ErrorAction Stop)
    $initial=@(Read-Addresses)
    if($binding.Count -ne 1 -or -not $binding[0].Enabled -or
        $initial.Count -ne 1 -or $initial[0] -ne '198.19.255.254/32/True'){
        throw 'The disposable unused interface must retain only its owned static bootstrap address.'
    }
}
$range=Get-Range $prefix
foreach($route in Get-NetRoute -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop){
    if($route.DestinationPrefix -eq '0.0.0.0/0'){continue}
    $other=Get-Range $route.DestinationPrefix
    if($other.First -le $range.Last -and $other.Last -ge $range.First){
        throw 'An existing route overlaps the exclusively owned cache-population prefix.'
    }
}
foreach($address in Get-NetIPAddress -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop){
    $other=Get-Range ($address.IPAddress+'/32')
    if($other.First -ge $range.First -and $other.First -le $range.Last){
        throw 'An existing address conflicts with the cache-population prefix.'
    }
}
if((@(Read-Defaults)-join '|') -ne (@($data.originalDefaultKeys)-join '|')){
    throw 'Default routing changed before path retirement.'
}
if($ReceiverProcessId -lt 1 -or -not(Test-Path -LiteralPath $ReceiverExecutable -PathType Leaf)){
    throw 'The verified receiver executable and process are required for bounded cohort observation.'
}
$null=[Reflection.Assembly]::Load([IO.File]::ReadAllBytes($ReceiverExecutable))
if((Read-PrefixPathCount) -ne 0){throw 'Existing cached paths conflict with the exclusively owned fixture prefix.'}
@{interfaceGuid=[string]$adapter[0].InterfaceGuid;source=$source;sources=$sources;prefix=$prefix
    originalAbsent=$true;originalAddresses=@(Read-Addresses);detachInterface=$detachInterface}|Export-Clixml -LiteralPath $StateFile -NoClobber
$sockets=[Collections.Generic.List[Net.Sockets.UdpClient]]::new()
$failure=$null;$restoreFailure=$null
$report=[ordered]@{schema=1;scenario=$(if($detachInterface){'owned-unused-interface-ipv4-detach'}else{'owned-secondary-source-address-retirement'});scope='owned-benchmark-state-only'
    triggerPhase=$(if($EndFile){'gc-complete-pre-released-cache'}else{'gc-start-then-socket-release'})
    requestedPaths=$PathCount;sourceCount=$sources.Count;measuredHeldPaths=0;measuredReleasedPaths=0;payloadsSent=0
    retired=$false;restored=$false;dataAndManagementAddressesPreserved=$false;defaultRoutesPreserved=$false}
try {
    foreach($address in $sources){
        $null=New-NetIPAddress -InterfaceIndex $adapter[0].ifIndex -IPAddress $address -PrefixLength 17 `
            -SkipAsSource $true -PolicyStore ActiveStore -ErrorAction Stop
    }
    $wait=[Diagnostics.Stopwatch]::StartNew()
    while(@(Read-OwnedAddress|Where-Object AddressState -eq 'Preferred').Count -ne $sources.Count){
        if($wait.Elapsed.TotalSeconds -gt 15){throw 'The owned secondary source did not become preferred.'}
        Start-Sleep -Milliseconds 50
    }
    $occupied=[Collections.Generic.HashSet[int]]::new()
    foreach($endpoint in Get-NetUDPEndpoint -ErrorAction Stop){$null=$occupied.Add([int]$endpoint.LocalPort)}
    $population=[Diagnostics.Stopwatch]::StartNew()
    foreach($address in $sources){
        $sockets.AddRange([ArrivalTcp]::CreateIdlePathSockets($address,($PathCount/$sources.Count),[int[]]@($occupied)))
    }
    $report.populationMilliseconds=$population.Elapsed.TotalMilliseconds
    $report.measuredHeldPaths=Read-PathCount
    if($report.measuredHeldPaths -lt $PathCount){throw 'The requested cached-path population did not verify.'}
    if(-not $EndFile){
        [IO.File]::WriteAllText($ReadyFile,'ready')
        Wait-ControlSignal $BeginFile 25
    }
    $release=[Diagnostics.Stopwatch]::StartNew()
    [ArrivalTcp]::ReleaseIdlePathSockets($sockets)
    $report.socketReleaseMilliseconds=$release.Elapsed.TotalMilliseconds
    $report.socketReleaseParallelism=[Environment]::ProcessorCount
    $sockets.Clear()
    if($EndFile){
        if((Read-PathCount) -lt $PathCount){throw 'Released cached paths did not persist before traffic.'}
        [IO.File]::WriteAllText($ReadyFile,'ready')
        Wait-ControlSignal $BeginFile
    }
    $report.snapshotStartedUtc=[DateTime]::UtcNow.ToString('o')
    $snapshotClock=[Diagnostics.Stopwatch]::StartNew()
    $report.measuredReleasedPaths=Read-PathCount
    $report.triggerPathSnapshotMilliseconds=$snapshotClock.Elapsed.TotalMilliseconds
    $report.triggerPathNativeQueryMilliseconds=$pathTiming.QueryMilliseconds
    $report.triggerPathRowScanMilliseconds=$pathTiming.RowScanMilliseconds
    if($report.measuredReleasedPaths -lt $PathCount){throw 'Released cached paths did not persist until retirement.'}
    $snapshotClock.Restart()
    $report.establishedAtSnapshot=[ArrivalTcp]::CountEstablishedConnections($ReceiverProcessId,20300)
    $report.triggerTcpSnapshotMilliseconds=$snapshotClock.Elapsed.TotalMilliseconds
    $report.snapshotCompletedUtc=[DateTime]::UtcNow.ToString('o')
    if($report.establishedAtSnapshot -lt 8){throw 'No verified live TCP cohort remains at the retirement snapshot.'}
    if($EndFile){
        if(Test-Path -LiteralPath $EndFile){throw 'GC completed before cache and cohort verification; no aligned retirement was attempted.'}
        Wait-ControlSignal $EndFile
        $report.gcCompletionObservedUtc=[DateTime]::UtcNow.ToString('o')
    }
    $report.controlStoppedBeforeRetirement=Test-Path -LiteralPath $StopFile
    if($report.controlStoppedBeforeRetirement){
        throw 'No verified live TCP cohort remains for the source-retirement control.'
    }
    $report.applyStartUtc=[DateTime]::UtcNow.ToString('o')
    if($detachInterface){
        $report.removeApiStartUtc=[DateTime]::UtcNow.ToString('o')
        Disable-NetAdapterBinding -Name $InterfaceAlias -ComponentID ms_tcpip -Confirm:$false -ErrorAction Stop
        $report.removeApiEndUtc=[DateTime]::UtcNow.ToString('o')
    }else{Restore-Control -MeasureRetirement}
    $report.applyEndUtc=[DateTime]::UtcNow.ToString('o')
    $report.retired=$true
    if($detachInterface){
        $hold=[Diagnostics.Stopwatch]::StartNew()
        while(-not(Test-Path -LiteralPath $StopFile)){
            if($hold.Elapsed.TotalSeconds -gt 180){throw 'The unused-interface restoration deadline was exceeded.'}
            Start-Sleep -Milliseconds 50
        }
    }
}catch{$failure=$_}
finally {
    [ArrivalTcp]::ReleaseIdlePathSockets($sockets)
    try {
        Restore-Control
        $report.restored=$true;$report.dataAndManagementAddressesPreserved=$true;$report.defaultRoutesPreserved=$true
    }catch{$restoreFailure=$_}
    $report.outcome=if($null -eq $failure -and $null -eq $restoreFailure){'completed'}else{'failed'}
    if($null -ne $failure){$report.failureType=$failure.Exception.GetType().FullName}
    if($null -ne $restoreFailure){
        $report.restoreFailureType=$restoreFailure.Exception.GetType().FullName
        $report.restoreFailureSourceLine=$restoreFailure.InvocationInfo.ScriptLineNumber
    }
    $report|ConvertTo-Json|Set-Content -LiteralPath $ReportFile
}
if($null -ne $failure -or $null -ne $restoreFailure){
    $errors=[Collections.Generic.List[Exception]]::new()
    if($null -ne $failure){$errors.Add($failure.Exception)}
    if($null -ne $restoreFailure){$errors.Add($restoreFailure.Exception)}
    throw [AggregateException]::new('The owned source-retirement control or restoration failed.',$errors)
}
