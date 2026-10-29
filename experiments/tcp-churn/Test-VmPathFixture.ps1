# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'adapters\VmPathFixture.psm1') -Force
$directory=Join-Path ([IO.Path]::GetTempPath()) ('vm-path-fixture-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $directory
try{
    foreach($case in @('cycle','two-connected','changed-vm','changed-adapter','guest-prepare-failure')){
        $stateFile=Join-Path $directory ($case+'.clixml')
        $fixture=@{VmId='11111111-1111-1111-1111-111111111111';Prepared=$false;Added=0;Removed=0;Connected=0
            Adapters=[Collections.Generic.List[object]]::new()}
        $fixture.Adapters.Add([pscustomobject]@{Id='original';Name='original-management';MacAddress='001122334455';SwitchName='existing-switch'})
        if($case -eq 'two-connected'){
            $fixture.Adapters.Add([pscustomobject]@{Id='other-original';Name='other-original';MacAddress='001122334466';SwitchName='other-switch'})
        }
        $fixture.OriginalCount=$fixture.Adapters.Count
        & (Get-Module VmPathFixture) {
            param($fixture,$case,$stateFile)
            function Get-VM {
                [CmdletBinding()]param($Name)
                [pscustomobject]@{Name=$Name;Id=$fixture.VmId;State='Running';Generation=2}
            }
            function Get-VMNetworkAdapter {
                [CmdletBinding()]param($VMName)
                $fixture.Adapters
            }
            function Add-VMNetworkAdapter {
                [CmdletBinding()]param($VMName,$Name,$StaticMacAddress,[switch]$Passthru)
                if($VMName -ne 'owned-test-vm' -or $Name -notmatch '^NetperfPath-[0-9a-f]{12}$' -or $StaticMacAddress -notmatch '^02[0-9A-F]{10}$'){
                    throw 'Unexpected fixture creation scope.'
                }
                $fixture.Added++
                $new=[pscustomobject]@{Id='owned-new';Name=$Name;MacAddress=$StaticMacAddress;SwitchName=''}
                $fixture.Adapters.Add($new)
                $new
            }
            function Invoke-Command {
                [CmdletBinding()]param($Session,$ScriptBlock,$ArgumentList)
                if($ScriptBlock.ToString().Contains('Find-NetRoute')){return '001122334455'}
                $new=@($fixture.Adapters|Where-Object Name -match '^NetperfPath-')[0]
                if($new.SwitchName -or -not $ScriptBlock.ToString().Contains('-Dhcp Disabled')){
                    throw 'The new interface was connected before static guest setup.'
                }
                if($case -eq 'guest-prepare-failure'){throw 'Synthetic guest preparation failure.'}
                $fixture.Prepared=$true
                [pscustomobject]@{alias=$ArgumentList[1];guid='22222222-2222-2222-2222-222222222222'}
            }
            function Connect-VMNetworkAdapter {
                [CmdletBinding()]param($VMNetworkAdapter,$SwitchName)
                if(-not $fixture.Prepared -or $VMNetworkAdapter.Id -ne 'owned-new' -or $SwitchName -ne 'existing-switch'){
                    throw 'The fixture connection changed an unowned interface or switch.'
                }
                $fixture.Connected++;$VMNetworkAdapter.SwitchName=$SwitchName
            }
            function Remove-VMNetworkAdapter {
                [CmdletBinding(SupportsShouldProcess=$true)]param($VMNetworkAdapter)
                if($VMNetworkAdapter.Name -eq 'original-management'){throw 'Original management interface removal was attempted.'}
                $fixture.Removed++;$null=$fixture.Adapters.Remove($VMNetworkAdapter)
            }
            $failed=$false
            try{
                $owned=New-TcpChurnVmPathFixture -VmName 'owned-test-vm' -Session 'unused' -StateFile $stateFile
                if($owned.Alias -notmatch '^NetperfPath-' -or $owned.Guid -ne '22222222-2222-2222-2222-222222222222'){
                    throw 'The owned guest interface identity was not returned.'
                }
                if($case -eq 'changed-vm'){$fixture.VmId='33333333-3333-3333-3333-333333333333'}
                if($case -eq 'changed-adapter'){(@($fixture.Adapters|Where-Object Name -match '^NetperfPath-')[0]).Id='unowned-replacement'}
                Remove-TcpChurnVmPathFixture -StateFile $stateFile
            }catch{
                $pattern=switch($case){
                    changed-vm {'VM identity changed'}
                    changed-adapter {'interface identity changed'}
                    guest-prepare-failure {'Synthetic guest preparation failure'}
                    default {'never-match-success-case'}
                }
                if($_.Exception.Message -notmatch $pattern){throw}
                $failed=$true
            }
            if($failed -ne ($case -notin @('cycle','two-connected'))){throw "Unexpected VM fixture verdict: $case"}
            if($case -in @('cycle','two-connected','guest-prepare-failure') -and ($fixture.Removed -ne 1 -or $fixture.Adapters.Count -ne $fixture.OriginalCount)){
                throw 'The owned interface was not removed on success or partial setup failure.'
            }
            if($case -in @('changed-vm','changed-adapter') -and $fixture.Removed){throw 'Changed ownership was not respected.'}
            if($fixture.Adapters[0].Name -ne 'original-management' -or $fixture.Adapters[0].SwitchName -ne 'existing-switch'){
                throw 'The original management interface changed.'
            }
        } $fixture $case $stateFile
    }
    Write-Output 'Passed 5 VM path-interface identity, source-MAC selection, disconnected-setup and rollback cases; Hyper-V commands were mocked.'
}finally{
    foreach($case in @('cycle','two-connected','changed-vm','changed-adapter','guest-prepare-failure')){
        $file=Join-Path $directory ($case+'.clixml')
        if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file}
    }
    Remove-Item -LiteralPath $directory
}
