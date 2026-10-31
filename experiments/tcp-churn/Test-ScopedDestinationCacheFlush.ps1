# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'adapters\Invoke-ScopedDestinationCacheFlush.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
$functions=@($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -in @('Invoke-OwnedDestinationFlush','Read-Defaults','Read-Addresses','Verify-NetworkSnapshot')
},$true))
if($functions.Count -ne 4){throw 'The actual destination-flush and configuration verification helpers must be identified.'}
. ([scriptblock]::Create(($functions|ForEach-Object{$_.Extent.Text})-join "`n"))
$directory=Join-Path ([IO.Path]::GetTempPath()) ('destination-flush-test-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $directory
try{
    foreach($case in @('valid','changed-owner','wrong-source','unowned-address','second-tool-failure')){
        & {
            $fixture=@{Calls=0}
            $adapter=[pscustomobject]@{Name='owned-interface';ifIndex=5;InterfaceGuid='test-interface'}
            $data=@{interfaceGuid='test-interface';originalDhcpDisabled=$true;addresses=@('198.19.240.1')}
            if($case -eq 'changed-owner'){$data.interfaceGuid='unowned-interface'}
            if($case -eq 'wrong-source'){$data.addresses=@('198.19.240.2')}
            if($case -eq 'unowned-address'){$data.addresses+='192.0.2.100'}
            $report=[ordered]@{destinationFlushes=0}
            function Invoke-TcpChurnTool {
                param($Program,$Arguments,$Directory,$LogPrefix,$TimeoutSeconds)
                $expected=if($fixture.Calls -eq 0){'198.19.240.1'}else{'198.19.240.6'}
                if($Program -ne "$env:SystemRoot\System32\netsh.exe" -or $Arguments.Count -ne 6 -or
                    ($Arguments[0..3]-join ' ') -ne 'interface ipv4 delete destinationcache' -or
                    $Arguments[4] -ne 'interface=owned-interface' -or $Arguments[5] -ne ('address='+$expected) -or
                    $TimeoutSeconds -ne 30){
                    throw 'A flush omitted its interface/destination scope or changed the owned endpoint allowlist.'
                }
                $fixture.Calls++
                if($case -eq 'second-tool-failure' -and $fixture.Calls -eq 2){throw 'Synthetic second flush failure.'}
            }
            $rejected=$false
            try{Invoke-OwnedDestinationFlush $adapter $data $report $directory}catch{
                $pattern=if($case -eq 'second-tool-failure'){'Synthetic second flush failure'}else{'exact owned data interface'}
                if($case -eq 'valid' -or $_.Exception.Message -notmatch $pattern){throw}
                $rejected=$true
            }
            $expectedCalls=if($case -in @('valid','second-tool-failure')){2}else{0}
            $expectedCompleted=if($case -eq 'valid'){2}elseif($case -eq 'second-tool-failure'){1}else{0}
            if($rejected -ne ($case -ne 'valid') -or $fixture.Calls -ne $expectedCalls -or
                $report.destinationFlushes -ne $expectedCompleted){
                throw 'An invalid scope reached netsh or a partial native failure was hidden.'
            }
        }
    }
    foreach($case in @('valid','changed-owner','changed-address','changed-default','changed-dhcp')){
        & {
            $InterfaceAlias='owned-interface';$StateFile=Join-Path $directory 'state.clixml'
            $adapter=@([pscustomobject]@{InterfaceGuid='test-interface';ifIndex=5})
            @{owner='tcp-churn-destination-flush-v1';interfaceGuid='test-interface'
                addresses=@('198.19.240.1/29/True');defaults=@('5/192.0.2.254/10')}|
                Export-Clixml -LiteralPath $StateFile
            function Get-NetAdapter {
                [CmdletBinding()]param($Name)
                [pscustomobject]@{InterfaceGuid=$(if($case -eq 'changed-owner'){'unowned-interface'}else{'test-interface'});ifIndex=5}
            }
            function Get-NetIPAddress {
                [CmdletBinding()]param($InterfaceIndex,$AddressFamily,$PolicyStore)
                [pscustomobject]@{IPAddress=$(if($case -eq 'changed-address'){'198.19.240.2'}else{'198.19.240.1'})
                    PrefixLength=29;SkipAsSource=$true;InterfaceIndex=5}
            }
            function Get-NetRoute {
                [CmdletBinding()]param($AddressFamily,$PolicyStore)
                [pscustomobject]@{DestinationPrefix='0.0.0.0/0';InterfaceIndex=5;RouteMetric=10
                    NextHop=$(if($case -eq 'changed-default'){'192.0.2.253'}else{'192.0.2.254'})}
            }
            function Get-NetIPInterface {
                [CmdletBinding()]param($InterfaceIndex,$AddressFamily)
                [pscustomobject]@{Dhcp=$(if($case -eq 'changed-dhcp'){'Enabled'}else{'Disabled'})}
            }
            $rejected=$false
            try{Verify-NetworkSnapshot}catch{
                if($case -eq 'valid' -or $_.Exception.Message -notmatch 'interface identity, addresses or default routing changed'){throw}
                $rejected=$true
            }
            if($rejected -ne ($case -ne 'valid')){throw 'Changed original network configuration was accepted.'}
            Remove-Item -LiteralPath $StateFile
        }
    }
    'Passed actual destination-flush exact endpoint/interface scopes, partial native failure and original network preservation checks; no networking was changed.'
}finally{
    $path=Join-Path $directory 'state.clixml'
    if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path}
    Remove-Item -LiteralPath $directory
}
