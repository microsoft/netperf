# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
$ErrorActionPreference='Stop'
$directory=Join-Path ([IO.Path]::GetTempPath()) ('unused-interface-restore-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $directory
try{
    $dataFile=Join-Path $directory 'data.clixml';$stateFile=Join-Path $directory 'state.clixml';$reportFile=Join-Path $directory 'report.json'
    $guid='22222222-2222-2222-2222-222222222222';$alias='NetperfPath-123456abcdef'
    foreach($primary in @($false,$true)){
        @{interfaceGuid=$(if($primary){$guid}else{'original-data-interface'});originalDhcpDisabled=$true
            addresses=@('198.19.240.1');originalDefaultKeys=@('7/192.0.2.254/10')}|Export-Clixml -LiteralPath $dataFile
        @{interfaceGuid=$guid;source='198.19.0.1';prefix='198.19.0.0/17';originalAbsent=$true
            originalAddresses=@('198.19.255.254/32/True');detachInterface=$true}|Export-Clixml -LiteralPath $stateFile
        $fixture=@{binding=$false;address=$true;writes=0;interfaceReads=0}
        $failed=$false
        try{
            & {
                function Get-NetAdapter {
                    [CmdletBinding()]param($Name)
                    [pscustomobject]@{InterfaceGuid=[guid]$guid;ifIndex=9}
                }
                function Get-NetAdapterBinding {
                    [CmdletBinding()]param($Name,$ComponentID)
                    [pscustomobject]@{Enabled=$fixture.binding}
                }
                function Enable-NetAdapterBinding {
                    [CmdletBinding(SupportsShouldProcess=$true)]param($Name,$ComponentID)
                    if($Name -ne $alias -or $ComponentID -ne 'ms_tcpip'){throw 'An unowned binding was enabled.'}
                    $fixture.binding=$true;$fixture.writes++
                }
                function Set-NetIPInterface {
                    [CmdletBinding()]param($InterfaceIndex,$AddressFamily,$Dhcp)
                    if($InterfaceIndex -ne 9 -or $Dhcp -ne 'Disabled' -or $fixture.interfaceReads -lt 2){
                        throw 'The original interface policy was touched or the rebound interface was not ready.'
                    }
                    $fixture.writes++
                }
                function Get-NetIPAddress {
                    [CmdletBinding()]param($InterfaceIndex,$AddressFamily,$PolicyStore)
                    [pscustomobject]@{InterfaceIndex=9;IPAddress='198.19.255.254';PrefixLength=32;SkipAsSource=$true}
                    if($fixture.address){
                        [pscustomobject]@{InterfaceIndex=9;IPAddress='198.19.0.1';PrefixLength=17;SkipAsSource=$true}
                    }
                }
                function Remove-NetIPAddress {
                    [CmdletBinding(SupportsShouldProcess=$true)]param($InterfaceIndex,$IPAddress,$PolicyStore)
                    if($InterfaceIndex -ne 9 -or $IPAddress -ne '198.19.0.1'){throw 'An unowned address was removed.'}
                    $fixture.address=$false;$fixture.writes++
                }
                function Get-NetRoute {
                    [CmdletBinding()]param($AddressFamily,$PolicyStore)
                    [pscustomobject]@{DestinationPrefix='0.0.0.0/0';InterfaceIndex=7;NextHop='192.0.2.254';RouteMetric=10}
                    if($fixture.address){[pscustomobject]@{DestinationPrefix='198.19.0.0/17';InterfaceIndex=9;NextHop='0.0.0.0';RouteMetric=256}}
                }
                function Get-NetIPInterface {
                    [CmdletBinding()]param($InterfaceIndex,$AddressFamily)
                    $fixture.interfaceReads++
                    if($fixture.interfaceReads -ge 2){[pscustomobject]@{InterfaceIndex=9;Dhcp='Disabled'}}
                }
                & (Join-Path $PSScriptRoot 'adapters\Invoke-ScopedPathRetirement.ps1') -InterfaceAlias $alias `
                    -UnusedInterfaceGuid $guid -DataStateFile $dataFile -StateFile $stateFile -ReportFile $reportFile -RestoreOnly
            }
        }catch{
            if(-not $primary -or $_.Exception.Message -notmatch 'requires owned receiver addresses'){throw}
            $failed=$true
        }
        if($primary){
            if(-not $failed -or $fixture.writes){throw 'The original data interface was accepted as disposable.'}
        }elseif(-not $fixture.binding -or $fixture.address -or $fixture.writes -ne 3){
            throw 'The unused binding/source/static-policy restoration did not verify.'
        }
    }
    Write-Output 'Passed disposable-interface restore and primary-interface rejection; network commands were mocked.'
}finally{
    foreach($name in @('data.clixml','state.clixml','report.json')){
        $file=Join-Path $directory $name
        if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file}
    }
    Remove-Item -LiteralPath $directory
}
