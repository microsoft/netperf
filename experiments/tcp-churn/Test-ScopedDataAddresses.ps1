# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
$ErrorActionPreference='Stop'
$directory=Join-Path ([IO.Path]::GetTempPath()) ('data-address-test-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $directory
$program=Join-Path $PSScriptRoot 'adapters\Set-ScopedDataAddresses.ps1'
$stateFile=Join-Path $directory 'state.clixml'
$reportFile=Join-Path $directory 'report.json'
$checks=0
try {
    foreach($case in @('roundtrip','peer-roundtrip','dhcp','overlap','existing-address','invalid-address','partial-add',
        'bad-manifest','changed-address','remove-failure','policy-drift')) {
        $fixture=@{dhcp='Disabled';newCalls=0;removes=0;failAdd=($case -eq 'partial-add');failRemove=($case -eq 'remove-failure')
            addresses=[Collections.Generic.List[object]]::new();routes=[Collections.Generic.List[object]]::new()}
        $fixture.addresses.Add([pscustomobject]@{IPAddress='192.0.2.1';PrefixLength=24;SkipAsSource=$false;AddressState='Preferred';InterfaceIndex=5})
        $fixture.routes.Add([pscustomobject]@{DestinationPrefix='0.0.0.0/0';NextHop='192.0.2.254';RouteMetric=10;InterfaceIndex=5})
        $fixture.routes.Add([pscustomobject]@{DestinationPrefix='192.0.2.0/24';NextHop='0.0.0.0';RouteMetric=256;InterfaceIndex=5})
        switch($case) {
            dhcp {$fixture.dhcp='Enabled'}
            overlap {$fixture.routes.Add([pscustomobject]@{DestinationPrefix='198.18.0.0/15';NextHop='192.0.2.254';RouteMetric=20;InterfaceIndex=5})}
            existing-address {$fixture.addresses.Add([pscustomobject]@{IPAddress='198.19.240.2';PrefixLength=32;SkipAsSource=$true;AddressState='Preferred';InterfaceIndex=7})}
        }
        $plan=if($case -eq 'invalid-address'){'198.19.240.7'}elseif($case -eq 'peer-roundtrip'){'198.19.240.5,198.19.240.6'}else{'198.19.240.1,198.19.240.2,198.19.240.3,198.19.240.4'}
        $expectedCount=$plan.Split(',').Count
        $failed=$false
        try {
            & {
                function Get-NetAdapter {
                    [CmdletBinding()]param($Name)
                    [pscustomobject]@{ifIndex=5;InterfaceGuid='test-interface'}
                }
                function Get-NetIPInterface {
                    [CmdletBinding()]param($InterfaceIndex,$AddressFamily)
                    [pscustomobject]@{Dhcp=$fixture.dhcp}
                }
                function Get-NetIPAddress {
                    [CmdletBinding()]param($InterfaceIndex,$AddressFamily,$PolicyStore)
                    if($PSBoundParameters.ContainsKey('InterfaceIndex')){$fixture.addresses|Where-Object InterfaceIndex -eq $InterfaceIndex}
                    else{$fixture.addresses}
                }
                function Get-NetRoute {
                    [CmdletBinding()]param($AddressFamily,$PolicyStore)
                    $fixture.routes
                }
                function New-NetIPAddress {
                    [CmdletBinding()]param($InterfaceIndex,$IPAddress,$PrefixLength,$SkipAsSource,$PolicyStore)
                    if($InterfaceIndex -ne 5 -or $PrefixLength -ne 29 -or $SkipAsSource -ne $true -or $PolicyStore -ne 'ActiveStore'){
                        throw 'Unexpected data-address mutation.'
                    }
                    $fixture.newCalls++
                    if($fixture.failAdd -and $fixture.newCalls -eq 2){throw 'Mock second address failed.'}
                    $fixture.addresses.Add([pscustomobject]@{IPAddress=$IPAddress;PrefixLength=29;SkipAsSource=$true;AddressState='Preferred';InterfaceIndex=5})
                    if(-not @($fixture.routes|Where-Object DestinationPrefix -eq '198.19.240.0/29').Count){
                        $fixture.routes.Add([pscustomobject]@{DestinationPrefix='198.19.240.0/29';NextHop='0.0.0.0';RouteMetric=256;InterfaceIndex=5})
                    }
                }
                function Remove-NetIPAddress {
                    [CmdletBinding(SupportsShouldProcess=$true)]
                    param($InterfaceIndex,$IPAddress,$PolicyStore)
                    if($InterfaceIndex -ne 5 -or $IPAddress -notin $plan.Split(',') -or $PolicyStore -ne 'ActiveStore'){
                        throw 'An unowned address removal was attempted.'
                    }
                    $fixture.removes++
                    if($fixture.failRemove){throw 'Mock owned address removal failed.'}
                    foreach($entry in @($fixture.addresses|Where-Object IPAddress -eq $IPAddress)){$null=$fixture.addresses.Remove($entry)}
                    if(-not @($fixture.addresses|Where-Object{$_.IPAddress -match '^198\.19\.240\.' -and $_.InterfaceIndex -eq 5}).Count){
                        foreach($entry in @($fixture.routes|Where-Object DestinationPrefix -eq '198.19.240.0/29')){$null=$fixture.routes.Remove($entry)}
                    }
                }
                & $program -Action add -InterfaceAlias 'test-only-interface' -Addresses $plan -StateFile $stateFile -ReportFile $reportFile
                $prepared=Get-Content $reportFile -Raw|ConvertFrom-Json
                if(-not $prepared.added -or $prepared.ownedAddressCount -ne $expectedCount){throw 'Data-address preparation did not report its exact plan.'}
                Remove-Item -LiteralPath $reportFile
                switch($case) {
                    bad-manifest {$saved=Import-Clixml $stateFile;$saved.interfaceGuid='other-interface';$saved|Export-Clixml $stateFile}
                    changed-address {($fixture.addresses|Where-Object IPAddress -eq '198.19.240.1').SkipAsSource=$false}
                    policy-drift {($fixture.routes|Where-Object DestinationPrefix -eq '0.0.0.0/0').NextHop='192.0.2.253'}
                }
                & $program -Action remove -InterfaceAlias 'test-only-interface' -Addresses $plan -StateFile $stateFile -ReportFile $reportFile
            }
        }catch {
            $pattern=switch($case) {
                dhcp {'already-static'}
                overlap {'existing route overlaps'}
                existing-address {'prefix is already in use'}
                invalid-address {'dedicated benchmark'}
                partial-add {'Mock second address failed'}
                bad-manifest {'snapshot does not match'}
                changed-address {'no longer matches'}
                remove-failure {'Mock owned address removal failed'}
                policy-drift {'Original management addresses'}
                default {'never-match-success-case'}
            }
            if($_.Exception.Message -notmatch $pattern){throw}
            $failed=$true
        }
        if($failed -ne ($case -notin @('roundtrip','peer-roundtrip'))){throw "Unexpected data-fixture verdict: $case"}
        if($case -in @('roundtrip','peer-roundtrip')) {
            $r=Get-Content $reportFile -Raw|ConvertFrom-Json
            if(-not $r.removed -or -not $r.managementPolicyPreserved -or
                $fixture.addresses.Count -ne 1 -or $fixture.newCalls -ne $expectedCount -or $fixture.removes -ne $expectedCount){
                throw 'The exact data fixture was not removed without changing management.'
            }
        }elseif(Test-Path $reportFile){throw 'A failed fixture operation published success.'}
        if($case -in @('dhcp','overlap','existing-address','invalid-address') -and ($fixture.newCalls -or $fixture.removes)){
            throw 'Rejected data-fixture admission mutated network state.'
        }
        if($case -eq 'partial-add' -and ($fixture.addresses.Count -ne 1 -or $fixture.removes -ne 1)){
            throw 'Partial data-address creation did not roll back.'
        }
        foreach($file in @($stateFile,$reportFile)){if(Test-Path $file){Remove-Item -LiteralPath $file}}
        $checks++
    }
}finally {
    foreach($file in @($stateFile,$reportFile)){if(Test-Path $file){Remove-Item -LiteralPath $file -ErrorAction Stop}}
    Remove-Item -LiteralPath $directory -ErrorAction Stop
}
Write-Output "Passed $checks scoped data-address cases; network operations were mocked and management policy was not changed."
