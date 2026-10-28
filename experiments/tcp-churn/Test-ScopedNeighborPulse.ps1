# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
$ErrorActionPreference='Stop'
$directory=Join-Path ([IO.Path]::GetTempPath()) ('neighbor-pulse-test-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $directory
$program=Join-Path $PSScriptRoot 'adapters\Invoke-ScopedNeighborPulse.ps1'
$stateFile=Join-Path $directory 'original.clixml'
$reportFile=Join-Path $directory 'report.json'
$checks=0
try {
    foreach($case in @('owned-permanent','already-dynamic','unresolved-dynamic','absent',
        'bad-manifest','unowned-mac','remove-failure')) {
        $snapshot=@{interfaceGuid='test-interface';localAddress='192.0.2.1';peerAddress='192.0.2.2'
            expectedMac='02-00-00-00-00-02';substituteMac='02-00-00-00-00-01';originalDynamic=$true}
        if($case -eq 'bad-manifest'){$snapshot.interfaceGuid='other-interface'}
        $snapshot|Export-Clixml -LiteralPath $stateFile
        $fixture=@{sets=0;removes=0;throwOnRemove=($case -eq 'remove-failure')
            current=@([pscustomobject]@{IPAddress='192.0.2.2';LinkLayerAddress='02-00-00-00-00-01';State='Permanent'})}
        switch($case) {
            already-dynamic {$fixture.current=@([pscustomobject]@{IPAddress='192.0.2.2';LinkLayerAddress='02-00-00-00-00-02';State='Reachable'})}
            unresolved-dynamic {$fixture.current=@([pscustomobject]@{IPAddress='192.0.2.2';LinkLayerAddress='00-00-00-00-00-00';State='Incomplete'})}
            absent {$fixture.current=@()}
            unowned-mac {$fixture.current=@([pscustomobject]@{IPAddress='192.0.2.2';LinkLayerAddress='02-00-00-00-00-03';State='Reachable'})}
        }
        $failed=$false
        try {
            & {
                function Import-Module { param($Name,[switch]$Force) }
                function Get-NetAdapter {
                    [CmdletBinding()]param($Name)
                    [pscustomobject]@{MacAddress='02-00-00-00-00-01';ifIndex=5;InterfaceGuid='test-interface'}
                }
                function Get-NetIPAddress {
                    [CmdletBinding()]param($InterfaceIndex,$AddressFamily)
                    [pscustomobject]@{IPAddress='192.0.2.1'}
                }
                function Get-NetIPInterface {
                    [CmdletBinding()]param($InterfaceIndex,$AddressFamily)
                    [pscustomobject]@{Forwarding='Disabled'}
                }
                function Get-NetNeighbor {
                    [CmdletBinding()]param($InterfaceAlias,$AddressFamily,$PolicyStore)
                    $fixture.current
                }
                function Invoke-TcpChurnTool {
                    param($Program,$Arguments,$Directory,$LogPrefix,$TimeoutSeconds)
                    if($Arguments.Count -ne 8 -or $Arguments[5] -ne '192.0.2.2' -or
                        $Arguments[6] -ne '02-00-00-00-00-02' -or $Arguments[7] -ne 'store=active'){
                        throw 'Restoration attempted an unexpected native operation.'
                    }
                    $fixture.sets++
                    $fixture.current=@([pscustomobject]@{IPAddress='192.0.2.2';LinkLayerAddress=$Arguments[6];State='Permanent'})
                    [pscustomobject]@{ExitCode=0}
                }
                function Remove-NetNeighbor {
                    [CmdletBinding(SupportsShouldProcess=$true)]
                    param($InterfaceAlias,$IPAddress,$PolicyStore)
                    if($IPAddress -ne '192.0.2.2' -or $PolicyStore -ne 'ActiveStore'){
                        throw 'Restoration attempted to remove an unowned neighbor.'
                    }
                    $fixture.removes++
                    if($fixture.throwOnRemove){throw 'Mock restoration removal failed.'}
                    $fixture.current=@()
                }
                & $program -RestoreOnly -InterfaceAlias 'test-only-interface' -LocalAddress '192.0.2.1' `
                    -PeerAddress '192.0.2.2' -ExpectedMac '02-00-00-00-00-02' -StateFile $stateFile -ReportFile $reportFile
            }
        }catch {
            if($case -notin @('bad-manifest','unowned-mac','remove-failure')){throw}
            $failed=$true
        }
        $expectedFailure=$case -in @('bad-manifest','unowned-mac','remove-failure')
        if($failed -ne $expectedFailure){throw "Unexpected restoration verdict: $case"}
        if($expectedFailure) {
            if(Test-Path -LiteralPath $reportFile){throw 'A failed restoration published a successful report.'}
            if($case -ne 'remove-failure' -and ($fixture.sets -ne 0 -or $fixture.removes -ne 0)){
                throw 'An unowned snapshot or neighbor caused a mutation.'
            }
        } else {
            $r=Get-Content $reportFile -Raw|ConvertFrom-Json
            $expectedChanges=if($case -in @('owned-permanent','unresolved-dynamic')){1}else{0}
            if(-not $r.restored -or $fixture.sets -ne $expectedChanges -or $fixture.removes -ne $expectedChanges){
                throw "Restoration did not preserve the original dynamic policy: $case"
            }
            Remove-Item -LiteralPath $reportFile
        }
        Remove-Item -LiteralPath $stateFile
        $checks++
    }
    foreach($case in @('loopback','missing-readiness')) {
        $rejected=$false
        $local=if($case -eq 'loopback'){'127.0.0.1'}else{'192.0.2.1'}
        try {
            & $program -InterfaceAlias 'unused-test-only' -LocalAddress $local -PeerAddress '192.0.2.2' `
                -ExpectedMac '02-00-00-00-00-02' -StateFile $stateFile -ReportFile $reportFile
        }catch {
            if($_.Exception.Message -notmatch 'requires non-loopback|requires its owned readiness'){throw}
            $rejected=$true
        }
        if(-not $rejected -or (Test-Path $stateFile) -or (Test-Path $reportFile)){throw 'Invalid pulse inputs mutated state or were accepted.'}
        $checks++
    }
}finally {
    foreach($file in @($stateFile,$reportFile)){if(Test-Path $file){Remove-Item -LiteralPath $file -ErrorAction Stop}}
    Remove-Item -LiteralPath $directory -ErrorAction Stop
}
Write-Output "Passed $checks scoped-neighbor pulse cases; network commands were mocked and no VM or network state was changed."
