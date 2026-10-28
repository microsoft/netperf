# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
$ErrorActionPreference='Stop'
$directory=Join-Path ([IO.Path]::GetTempPath()) ('path-retire-test-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $directory
$program=Join-Path $PSScriptRoot 'adapters\Invoke-ScopedPathRetirement.ps1'
$checks=0
try {
    foreach($case in @('restore','already-absent','bad-data','changed-owner','changed-prefix','changed-default','remove-failure','overlap-route','overlap-address')){
        $dataFile=Join-Path $directory 'data.clixml';$stateFile=Join-Path $directory 'state.clixml';$reportFile=Join-Path $directory 'report.json'
        $data=@{interfaceGuid='test-interface';originalDhcpDisabled=$true
            addresses=@('198.19.240.1','198.19.240.2','198.19.240.3','198.19.240.4')
            originalDefaultKeys=@('5/192.0.2.254/10')}
        if($case -eq 'bad-data'){$data.interfaceGuid='unowned-interface'}
        $data|Export-Clixml -LiteralPath $dataFile
        $fixture=@{removes=0;addresses=[Collections.Generic.List[object]]::new()
            routes=[Collections.Generic.List[object]]::new()}
        $fixture.addresses.Add([pscustomobject]@{IPAddress='198.19.240.1';PrefixLength=29;SkipAsSource=$true;InterfaceIndex=5})
        $fixture.routes.Add([pscustomobject]@{DestinationPrefix='0.0.0.0/0';NextHop='192.0.2.254';RouteMetric=10;InterfaceIndex=5})
        if($case -eq 'changed-default'){$fixture.routes[0].NextHop='192.0.2.253'}
        $restore=$case -notin @('bad-data','overlap-route','overlap-address')
        if($restore){
            @{interfaceGuid='test-interface';source='198.19.0.1';prefix='198.19.0.0/17';originalAbsent=$true
                originalAddresses=@('198.19.240.1/29/True')}|Export-Clixml -LiteralPath $stateFile
        }
        if($case -in @('restore','changed-owner','changed-prefix','remove-failure','overlap-address')){
            $index=if($case -eq 'changed-owner'){6}else{5}
            $bits=if($case -eq 'changed-prefix'){24}else{17}
            $fixture.addresses.Add([pscustomobject]@{IPAddress='198.19.0.1';PrefixLength=$bits;SkipAsSource=$true;InterfaceIndex=$index})
            $fixture.routes.Add([pscustomobject]@{DestinationPrefix='198.19.0.0/17';NextHop='0.0.0.0';RouteMetric=256;InterfaceIndex=5})
        }
        if($case -eq 'overlap-address'){$fixture.routes.RemoveAt(1)}
        if($case -eq 'overlap-route'){
            $fixture.routes.Add([pscustomobject]@{DestinationPrefix='198.18.0.0/15';NextHop='192.0.2.254';RouteMetric=10;InterfaceIndex=5})
        }
        $failed=$false
        try {
            & {
                function Get-NetAdapter {
                    [CmdletBinding()]param($Name)
                    [pscustomobject]@{InterfaceGuid='test-interface';ifIndex=5}
                }
                function Get-NetIPAddress {
                    [CmdletBinding()]param($InterfaceIndex,$AddressFamily,$PolicyStore)
                    $fixture.addresses|Where-Object{-not $PSBoundParameters.ContainsKey('InterfaceIndex') -or $_.InterfaceIndex -eq $InterfaceIndex}
                }
                function Get-NetRoute {
                    [CmdletBinding()]param($AddressFamily,$PolicyStore)
                    $fixture.routes
                }
                function Get-NetIPInterface {
                    [CmdletBinding()]param($InterfaceIndex,$AddressFamily)
                    [pscustomobject]@{Dhcp='Disabled'}
                }
                function Remove-NetIPAddress {
                    [CmdletBinding(SupportsShouldProcess=$true)]
                    param($InterfaceIndex,$IPAddress,$PolicyStore)
                    if($InterfaceIndex -ne 5 -or $IPAddress -ne '198.19.0.1' -or $PolicyStore -ne 'ActiveStore'){
                        throw 'An unowned address removal was attempted.'
                    }
                    $fixture.removes++
                    if($case -eq 'remove-failure'){throw 'Synthetic removal failure.'}
                    foreach($entry in @($fixture.addresses|Where-Object IPAddress -eq $IPAddress)){$null=$fixture.addresses.Remove($entry)}
                    foreach($entry in @($fixture.routes|Where-Object DestinationPrefix -eq '198.19.0.0/17')){$null=$fixture.routes.Remove($entry)}
                }
                function New-NetIPAddress {throw 'Preflight tests must never mutate addresses.'}
                $extra=if($restore){@{RestoreOnly=$true}}else{@{ReadyFile='unused';BeginFile='unused';StopFile='unused'}}
                & $program -InterfaceAlias 'test-only-interface' -DataStateFile $dataFile -StateFile $stateFile -ReportFile $reportFile @extra
            }
        }catch{
            $pattern=switch($case){
                bad-data {'requires owned receiver addresses'}
                changed-owner {'changed ownership'}
                changed-prefix {'changed ownership'}
                changed-default {'unchanged default routes'}
                remove-failure {'Synthetic removal failure'}
                overlap-route {'existing route overlaps'}
                overlap-address {'existing address conflicts'}
                default {'never-match-success-case'}
            }
            if($_.Exception.Message -notmatch $pattern){throw}
            $failed=$true
        }
        if($failed -ne ($case -notin @('restore','already-absent'))){throw "Unexpected retirement verdict: $case"}
        if($case -in @('bad-data','changed-owner','changed-prefix','overlap-route','overlap-address') -and $fixture.removes){
            throw 'Rejected ownership or overlap mutated state.'
        }
        if($case -eq 'restore' -and ($fixture.removes -ne 1 -or $fixture.addresses.Count -ne 1)){
            throw 'The owned source was not exclusively retired.'
        }
        foreach($file in @($dataFile,$stateFile,$reportFile)){if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file}}
        $checks++
    }
    Write-Host "Passed $checks source-retirement ownership and restoration cases; no network operations were performed."
}finally{
    foreach($name in @('data.clixml','state.clixml','report.json')){
        $file=Join-Path $directory $name
        if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file}
    }
    Remove-Item -LiteralPath $directory -ErrorAction Stop
}
