# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
$ErrorActionPreference='Stop'
$directory=Join-Path ([IO.Path]::GetTempPath()) ('cluster-scope-test-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $directory
$checks=0
try{
    $addressScript=Join-Path $PSScriptRoot 'adapters\Set-ScopedClusterAddresses.ps1'
    foreach($case in @('add-remove','foreign-address','overlap-route','rollback')){
        $state=Join-Path $directory "$case.clixml";$report=Join-Path $directory "$case.json"
        $fixture=@{addresses=[Collections.Generic.List[object]]::new();adds=0;removes=0
            routes=@([pscustomobject]@{DestinationPrefix='0.0.0.0/0';InterfaceIndex=5;NextHop='192.0.2.1';RouteMetric=10})}
        $fixture.addresses.Add([pscustomobject]@{IPAddress='198.19.240.6';InterfaceIndex=5;PrefixLength=29;SkipAsSource=$true;AddressState='Preferred'})
        if($case -eq 'overlap-route'){$fixture.routes+=[pscustomobject]@{DestinationPrefix='198.19.66.0/24';InterfaceIndex=5;NextHop='0.0.0.0';RouteMetric=1}}
        $failed=$false
        try{
            & {
                function Get-NetAdapter {[CmdletBinding()]param($Name)[pscustomobject]@{InterfaceGuid='g';ifIndex=5}}
                function Get-NetIPInterface {[CmdletBinding()]param($InterfaceIndex,$AddressFamily)[pscustomobject]@{Dhcp='Disabled'}}
                function Get-NetIPAddress {[CmdletBinding()]param($InterfaceIndex,$AddressFamily,$PolicyStore)
                    $fixture.addresses|Where-Object{-not $PSBoundParameters.ContainsKey('InterfaceIndex') -or $_.InterfaceIndex -eq $InterfaceIndex}}
                function Get-NetRoute {[CmdletBinding()]param($AddressFamily,$PolicyStore)$fixture.routes}
                function New-NetIPAddress {[CmdletBinding()]param($InterfaceIndex,$IPAddress,$PrefixLength,$SkipAsSource,$PolicyStore)
                    if($IPAddress -notmatch '^198\.19\.6[4-7]\.' -or $PrefixLength -ne 32 -or -not $SkipAsSource){throw 'Unowned address plan.'}
                    $fixture.adds++
                    if($case -eq 'rollback' -and $fixture.adds -eq 10){throw 'Synthetic add failure.'}
                    $fixture.addresses.Add([pscustomobject]@{IPAddress=$IPAddress;InterfaceIndex=5;PrefixLength=32;SkipAsSource=$true;AddressState='Preferred'})}
                function Remove-NetIPAddress {[CmdletBinding(SupportsShouldProcess=$true)]param($InterfaceIndex,$IPAddress,$PolicyStore)
                    if($IPAddress -notmatch '^198\.19\.6[4-7]\.'){throw 'Unowned removal.'}
                    $fixture.removes++
                    $row=@($fixture.addresses|Where-Object IPAddress -eq $IPAddress)[0];$null=$fixture.addresses.Remove($row)}
                & $addressScript -Action add -InterfaceAlias 'data' -Count 64 -StateFile $state -ReportFile $report
                if($case -eq 'foreign-address'){
                    $fixture.addresses.Add([pscustomobject]@{IPAddress='198.19.67.251';InterfaceIndex=5;PrefixLength=32;SkipAsSource=$true;AddressState='Preferred'})
                }
                & $addressScript -Action remove -InterfaceAlias 'data' -Count 64 -StateFile $state -ReportFile $report
            }
        }catch{
            $pattern=switch($case){'foreign-address'{'not owned'}'overlap-route'{'overlaps'}'rollback'{'Synthetic add failure'}default{'never'}}
            if($_.Exception.Message -notmatch $pattern){throw}
            $failed=$true
        }
        if($failed -ne ($case -ne 'add-remove')){throw "Unexpected cluster-address verdict: $case"}
        if($case -eq 'add-remove' -and ($fixture.adds -ne 64 -or $fixture.removes -ne 64 -or $fixture.addresses.Count -ne 1)){
            throw 'Cluster addresses were not exactly added and restored.'
        }
        if($case -eq 'overlap-route' -and $fixture.adds){throw 'An overlapping prefix was mutated.'}
        if($case -eq 'foreign-address' -and ($fixture.removes -or $fixture.addresses.Count -ne 66)){throw 'Foreign ownership did not stop all removal.'}
        if($case -eq 'rollback' -and ($fixture.removes -ne 9 -or $fixture.addresses.Count -ne 1)){throw 'Partial preparation was not rolled back.'}
        foreach($file in @($state,$report)){if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file}}
        $checks++
    }
    $routeScript=Join-Path $PSScriptRoot 'adapters\Set-ScopedClusterRoutes.ps1'
    foreach($case in @('add-remove','foreign-route','existing')){
        $state=Join-Path $directory "route-$case.clixml";$report=Join-Path $directory "route-$case.json"
        $fixture=@{routes=[Collections.Generic.List[object]]::new();adds=0;removes=0}
        $fixture.routes.Add([pscustomobject]@{DestinationPrefix='0.0.0.0/0';InterfaceIndex=5;NextHop='192.0.2.1';RouteMetric=10})
        if($case -eq 'existing'){$fixture.routes.Add([pscustomobject]@{DestinationPrefix='198.19.64.0/22';InterfaceIndex=7;NextHop='192.0.2.9';RouteMetric=1})}
        $failed=$false
        try{
            & {
                function Get-NetAdapter {[CmdletBinding()]param($Name)[pscustomobject]@{InterfaceGuid='g';ifIndex=5}}
                function Get-NetRoute {[CmdletBinding()]param($AddressFamily,$PolicyStore)$fixture.routes}
                function Get-NetIPAddress {[CmdletBinding()]param($InterfaceIndex,$AddressFamily,$PolicyStore)
                    [pscustomobject]@{IPAddress='198.19.240.1';PrefixLength=29}}
                function New-NetRoute {[CmdletBinding()]param($InterfaceIndex,$DestinationPrefix,$NextHop,$RouteMetric,$PolicyStore)
                    if($DestinationPrefix -ne '198.19.64.0/22' -or $NextHop -notin @('198.19.240.5','198.19.240.6')){throw 'Unowned route.'}
                    $fixture.adds++
                    $fixture.routes.Add([pscustomobject]@{DestinationPrefix=$DestinationPrefix;InterfaceIndex=$InterfaceIndex;NextHop=$NextHop;RouteMetric=$RouteMetric})}
                function Remove-NetRoute {[CmdletBinding(SupportsShouldProcess=$true)]param($InterfaceIndex,$DestinationPrefix,$NextHop,$PolicyStore)
                    $fixture.removes++
                    $row=@($fixture.routes|Where-Object{$_.DestinationPrefix -eq $DestinationPrefix -and $_.NextHop -eq $NextHop})[0]
                    $null=$fixture.routes.Remove($row)}
                & $routeScript -Action add -InterfaceAlias 'data' -StateFile $state -ReportFile $report
                if($case -eq 'foreign-route'){
                    $fixture.routes.Add([pscustomobject]@{DestinationPrefix='198.19.64.0/22';InterfaceIndex=5;NextHop='198.19.240.4';RouteMetric=1})
                }
                & $routeScript -Action remove -InterfaceAlias 'data' -StateFile $state -ReportFile $report
            }
        }catch{
            $pattern=switch($case){'foreign-route'{'not owned'}'existing'{'already has routes'}default{'never'}}
            if($_.Exception.Message -notmatch $pattern){throw}
            $failed=$true
        }
        if($failed -ne ($case -ne 'add-remove')){throw "Unexpected cluster-route verdict: $case"}
        if($case -eq 'add-remove' -and ($fixture.adds -ne 2 -or $fixture.removes -ne 2 -or $fixture.routes.Count -ne 1)){
            throw 'Cluster routes were not exactly added and restored.'
        }
        if($case -ne 'add-remove' -and $fixture.removes){throw 'A rejected route state was mutated.'}
        foreach($file in @($state,$report)){if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file}}
        $checks++
    }
    $outageScript=Join-Path $PSScriptRoot 'adapters\Invoke-ScopedPeerOutage.ps1'
    foreach($case in @('applied','stopped-before','not-owned','remove-failure')){
        $ready=Join-Path $directory "outage-$case.ready";$stop=Join-Path $directory "outage-$case.stop";$report=Join-Path $directory "outage-$case.json"
        $rule='NetperfClusterOutage-'+[guid]::NewGuid().ToString('N')
        $fixture=@{rules=[Collections.Generic.HashSet[string]]::new();created=0}
        if($case -eq 'stopped-before'){[IO.File]::WriteAllText($stop,'stop')}
        $failed=$false
        try{
            & {
                function Get-NetIPAddress {[CmdletBinding()]param($IPAddress,$AddressFamily)
                    if($case -eq 'not-owned'){return}
                    [pscustomobject]@{IPAddress=$IPAddress}}
                function Get-NetFirewallRule {[CmdletBinding()]param($Name,$PolicyStore)
                    if($fixture.rules.Contains($Name)){[pscustomobject]@{Name=$Name}}}
                function New-NetFirewallRule {[CmdletBinding()]param($Name,$DisplayName,$Direction,$Action,$Protocol,$LocalAddress,$PolicyStore)
                    if($Name -ne $rule -or $Action -ne 'Block' -or $Direction -ne 'Inbound' -or @($LocalAddress).Count -ne 2){throw 'Unowned outage rule.'}
                    $fixture.created++;$null=$fixture.rules.Add($Name)}
                function Remove-NetFirewallRule {[CmdletBinding()]param($Name,$PolicyStore)
                    if($case -eq 'remove-failure'){throw 'Synthetic rule removal failure.'}
                    $null=$fixture.rules.Remove($Name)}
                & $outageScript -Addresses '198.19.64.1,198.19.64.5' -DelayMilliseconds 1000 -DurationMilliseconds 500 `
                    -ReadyFile $ready -StopFile $stop -ReportFile $report -RuleName $rule
            }
        }catch{
            $pattern=switch($case){'not-owned'{'owned local cluster'}'remove-failure'{'Synthetic rule removal'}default{'never'}}
            if($_.Exception.Message -notmatch $pattern){throw}
            $failed=$true
        }
        if($failed -ne ($case -in @('not-owned','remove-failure'))){throw "Unexpected outage verdict: $case"}
        if($case -ne 'not-owned'){
            $result=Get-Content -LiteralPath $report -Raw|ConvertFrom-Json
            if($case -eq 'applied' -and (-not $result.applied -or -not $result.removed -or $fixture.rules.Count -or $result.outcome -ne 'completed')){
                throw 'The bounded outage did not apply and restore.'
            }
            if($case -eq 'stopped-before' -and ($result.applied -or $fixture.created -or -not $result.stoppedBeforeOutage)){
                throw 'A completed workload still started its outage.'
            }
            if($case -eq 'remove-failure' -and ($result.removed -or $result.outcome -ne 'failed')){
                throw 'An unremoved outage rule was reported as restored.'
            }
        }elseif($fixture.created){throw 'A non-owned outage address mutated firewall policy.'}
        foreach($file in @($ready,$stop,$report)){if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file}}
        $checks++
    }
}finally{Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue}
Write-Output "Passed $checks cluster address, route and bounded-outage ownership cases; no network operations were performed."
