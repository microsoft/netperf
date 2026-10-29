# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition @'
public static class NetperfRssNative {
    public static ushort GetActiveProcessorGroupCount() { return 2; }
    public static uint GetActiveProcessorCount(ushort group) { return 40; }
}
'@
$directory=Join-Path ([IO.Path]::GetTempPath()) ('scoped-rss-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $directory
try{
    foreach($case in @('cycle','partial-readback','changed-identity')){
        $fixture=@{Guid='owned-interface';Writes=0;ArrayCount=20
            Settings=@{Enabled=$true;Profile='NUMAStatic';Queues=20;MaxProcessors=20;BaseGroup=0;BaseNumber=0;MaxGroup=0;MaxNumber=19}}
        $stateFile=Join-Path $directory 'state.clixml';$reportFile=Join-Path $directory 'report.json'
        & {
            function Get-NetAdapter {
                [CmdletBinding()]param($Name)
                [pscustomobject]@{Name=$Name;InterfaceGuid=$fixture.Guid;ifIndex=5}
            }
            function Get-NetAdapterRss {
                [CmdletBinding()]param($Name)
                $s=$fixture.Settings
                [pscustomobject]@{Enabled=$s.Enabled;Profile=$s.Profile;NumberOfReceiveQueues=$s.Queues
                    MaxProcessors=$s.MaxProcessors;BaseProcessorGroup=$s.BaseGroup;BaseProcessorNumber=$s.BaseNumber
                    MaxProcessorGroup=$s.MaxGroup;MaxProcessorNumber=$s.MaxNumber;RssProcessorArray=@(1..$fixture.ArrayCount)}
            }
            function Set-NetAdapterRss {
                [CmdletBinding()]param($Name,$Enabled,$Profile,$NumberOfReceiveQueues,$MaxProcessors,
                    $BaseProcessorGroup,$BaseProcessorNumber,$MaxProcessorGroup,$MaxProcessorNumber,[switch]$NoRestart)
                if($Name -ne 'owned-data' -or -not $NoRestart){throw 'RSS attempted to mutate an unowned adapter or restart it.'}
                $fixture.Writes++
                $fixture.Settings=@{Enabled=$Enabled;Profile=$Profile;Queues=$NumberOfReceiveQueues;MaxProcessors=$MaxProcessors
                    BaseGroup=$BaseProcessorGroup;BaseNumber=$BaseProcessorNumber;MaxGroup=$MaxProcessorGroup;MaxNumber=$MaxProcessorNumber}
                $fixture.ArrayCount=if($case -eq 'partial-readback' -and $fixture.Writes -eq 1){20}else{$MaxProcessors}
            }
            function Get-CimInstance {
                [CmdletBinding()]param($ClassName)
                [pscustomobject]@{NumberOfLogicalProcessors=80}
            }
            function Get-NetIPAddress {
                [CmdletBinding()]param($AddressFamily)
                [pscustomobject]@{InterfaceIndex=5;IPAddress='192.0.2.1';PrefixLength=24;SkipAsSource=$false}
                [pscustomobject]@{InterfaceIndex=9;IPAddress='198.19.255.254';PrefixLength=32;SkipAsSource=$true}
            }
            function Get-NetRoute {
                [CmdletBinding()]param($AddressFamily,$PolicyStore)
                [pscustomobject]@{DestinationPrefix='0.0.0.0/0';InterfaceIndex=5;NextHop='192.0.2.254';RouteMetric=10}
            }
            $program=Join-Path $PSScriptRoot 'adapters\Set-ScopedRss.ps1'
            $prepareFailed=$false
            try{& $program -Action prepare -InterfaceAlias 'owned-data' -Processors 64 -StateFile $stateFile -ReportFile $reportFile}catch{
                if($case -ne 'partial-readback' -or $_.Exception.Message -notmatch 'active RSS processor array'){throw}
                $prepareFailed=$true
            }
            if($prepareFailed -ne ($case -eq 'partial-readback')){throw 'Unexpected RSS preparation verdict.'}
            if($fixture.Settings.MaxGroup -ne 1 -or $fixture.Settings.MaxNumber -ne 23){
                throw 'RSS assumed 64 active processors per group instead of the observed 40/40 layout.'
            }
            if($case -eq 'changed-identity'){$fixture.Guid='unowned-replacement'}
            $restoreFailed=$false
            try{& $program -Action restore -StateFile $stateFile -ReportFile $reportFile}catch{
                if($case -ne 'changed-identity' -or $_.Exception.Message -notmatch 'identity changed'){throw}
                $restoreFailed=$true
            }
            if($case -eq 'changed-identity'){
                if(-not $restoreFailed -or $fixture.Writes -ne 1){throw 'Changed RSS ownership was not protected.'}
            }elseif($restoreFailed -or $fixture.Writes -ne 2 -or $fixture.Settings.Queues -ne 20 -or $fixture.ArrayCount -ne 20){
                throw 'The original RSS fields and active processor array did not restore after success or partial preparation.'
            }
        }
        foreach($file in @($stateFile,$reportFile)){if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file}}
    }
    Write-Output 'Passed scoped RSS processor-group, active-readback, rollback and identity checks; adapter commands were mocked.'
}finally{
    foreach($name in @('state.clixml','report.json')){
        $file=Join-Path $directory $name
        if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file}
    }
    Remove-Item -LiteralPath $directory
}
