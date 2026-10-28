# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
$ErrorActionPreference='Stop'
$directory=Join-Path ([IO.Path]::GetTempPath()) ('path-refresh-test-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $directory
$program=Join-Path $PSScriptRoot 'adapters\Invoke-ScopedPathRefresh.ps1'
$dataFile=Join-Path $directory 'data.clixml'
$stateFile=Join-Path $directory 'route.clixml'
$reportFile=Join-Path $directory 'report.json'
$readyFile=Join-Path $directory 'ready'
$beginFile=Join-Path $directory 'begin'
$stopFile=Join-Path $directory 'stop'
$checks=0
try {
    foreach($case in @('cycle','already-absent','bad-data','host-conflict','changed-route','add-failure','remove-failure','default-drift')) {
        $data=@{interfaceGuid='test-interface';originalDhcpDisabled=$true;addresses=@('198.19.240.1')
            originalDefaultKeys=@('5/192.0.2.254/10')}
        if($case -eq 'bad-data'){$data.interfaceGuid='unowned-interface'}
        $data|Export-Clixml -LiteralPath $dataFile
        $fixture=@{adds=0;removes=0;failAdd=($case -eq 'add-failure');failRemove=($case -eq 'remove-failure')
            routes=[Collections.Generic.List[object]]::new()}
        $fixture.routes.Add([pscustomobject]@{DestinationPrefix='0.0.0.0/0';NextHop='192.0.2.254';RouteMetric=10;InterfaceIndex=5})
        $fixture.routes.Add([pscustomobject]@{DestinationPrefix='198.19.240.0/29';NextHop='0.0.0.0';RouteMetric=256;InterfaceIndex=5})
        $restore=$case -in @('already-absent','changed-route','default-drift')
        if($restore) {
            @{interfaceGuid='test-interface';prefix='198.19.240.6/32';nextHop='0.0.0.0';metric=1;originalAbsent=$true}|
                Export-Clixml -LiteralPath $stateFile
        }
        if($case -in @('host-conflict','changed-route','default-drift')){
            $metric=if($case -eq 'changed-route'){2}else{1}
            $fixture.routes.Add([pscustomobject]@{DestinationPrefix='198.19.240.6/32';NextHop='0.0.0.0';RouteMetric=$metric;InterfaceIndex=5})
        }
        if($case -eq 'default-drift'){($fixture.routes|Where-Object DestinationPrefix -eq '0.0.0.0/0').NextHop='192.0.2.253'}
        [IO.File]::WriteAllText($beginFile,'synthetic-pre-call')
        $failed=$false
        try {
            & {
                function Get-NetAdapter {
                    [CmdletBinding()]param($Name)
                    [pscustomobject]@{ifIndex=5;InterfaceGuid='test-interface'}
                }
                function Get-NetIPInterface {
                    [CmdletBinding()]param($InterfaceIndex,$AddressFamily)
                    [pscustomobject]@{Dhcp='Disabled'}
                }
                function Get-NetIPAddress {
                    [CmdletBinding()]param($InterfaceIndex,$AddressFamily,$PolicyStore)
                    [pscustomobject]@{IPAddress='198.19.240.1';PrefixLength=29;SkipAsSource=$true}
                }
                function Get-NetRoute {
                    [CmdletBinding()]param($AddressFamily,$PolicyStore)
                    $fixture.routes
                }
                function New-NetRoute {
                    [CmdletBinding()]param($InterfaceIndex,$DestinationPrefix,$NextHop,$RouteMetric,$PolicyStore)
                    if($InterfaceIndex -ne 5 -or $DestinationPrefix -ne '198.19.240.6/32' -or
                        $NextHop -ne '0.0.0.0' -or $RouteMetric -ne 1 -or $PolicyStore -ne 'ActiveStore'){
                        throw 'An unowned route addition was attempted.'
                    }
                    $fixture.adds++
                    if($fixture.failAdd){throw 'Mock route addition failed.'}
                    $fixture.routes.Add([pscustomobject]@{DestinationPrefix=$DestinationPrefix;NextHop=$NextHop;RouteMetric=$RouteMetric;InterfaceIndex=5})
                }
                function Remove-NetRoute {
                    [CmdletBinding(SupportsShouldProcess=$true)]
                    param($InterfaceIndex,$DestinationPrefix,$NextHop,$PolicyStore)
                    if($InterfaceIndex -ne 5 -or $DestinationPrefix -ne '198.19.240.6/32' -or
                        $NextHop -ne '0.0.0.0' -or $PolicyStore -ne 'ActiveStore'){throw 'An unowned route removal was attempted.'}
                    $fixture.removes++
                    if($fixture.failRemove){throw 'Mock route removal failed.'}
                    foreach($entry in @($fixture.routes|Where-Object DestinationPrefix -eq $DestinationPrefix)){$null=$fixture.routes.Remove($entry)}
                }
                $extra=if($restore){@{RestoreOnly=$true}}else{@{ReadyFile=$readyFile;BeginFile=$beginFile;StopFile=$stopFile;MaximumHoldMilliseconds=100}}
                & $program -InterfaceAlias 'test-only-interface' -DataStateFile $dataFile -StateFile $stateFile -ReportFile $reportFile @extra
            }
        }catch {
            $pattern=switch($case) {
                bad-data {'verified owned client data fixture'}
                host-conflict {'existing host route conflicts'}
                changed-route {'changed ownership'}
                default-drift {'unchanged default routing'}
                add-failure {'control or restoration failed'}
                remove-failure {'control or restoration failed'}
                default {'never-match-success-case'}
            }
            if($_.Exception.Message -notmatch $pattern){throw}
            $failed=$true
        }
        if($failed -ne ($case -notin @('cycle','already-absent'))){throw "Unexpected route-control verdict: $case"}
        if($case -eq 'cycle') {
            $r=Get-Content $reportFile -Raw|ConvertFrom-Json
            if($r.outcome -ne 'completed' -or -not $r.added -or -not $r.removed -or -not $r.defaultRoutesPreserved -or
                $fixture.adds -ne 1 -or $fixture.removes -ne 1 -or $fixture.routes.Count -ne 2){
                throw 'The one-route control did not preserve original routing.'
            }
        }
        if($case -in @('bad-data','host-conflict','changed-route') -and ($fixture.adds -or $fixture.removes)){
            throw 'Rejected ownership or route conflict mutated state.'
        }
        if($case -eq 'remove-failure') {
            $r=Get-Content $reportFile -Raw|ConvertFrom-Json
            if($r.outcome -ne 'failed' -or $r.removed -or $r.defaultRoutesPreserved){throw 'A failed route restoration was reported as success.'}
        }
        foreach($file in @($dataFile,$stateFile,$reportFile,$readyFile,$beginFile,$stopFile)){
            if(Test-Path $file){Remove-Item -LiteralPath $file}
        }
        $checks++
    }
}finally {
    foreach($file in @($dataFile,$stateFile,$reportFile,$readyFile,$beginFile,$stopFile)){
        if(Test-Path $file){Remove-Item -LiteralPath $file -ErrorAction Stop}
    }
    Remove-Item -LiteralPath $directory -ErrorAction Stop
}
Write-Output "Passed $checks scoped path-refresh ownership/restoration cases; network commands were mocked."
