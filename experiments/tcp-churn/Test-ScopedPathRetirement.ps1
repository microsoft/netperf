# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
$ErrorActionPreference='Stop'
$directory=Join-Path ([IO.Path]::GetTempPath()) ('path-retire-test-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $directory
$program=Join-Path $PSScriptRoot 'adapters\Invoke-ScopedPathRetirement.ps1'
$checks=0
try {
    foreach($case in @('restore','already-absent','bad-data','changed-owner','changed-prefix','changed-default','remove-failure','overlap-route','overlap-address','restore-two','restore-partial-two','changed-second-owner',
        'data-restore','data-restore-disabled','data-restore-two','data-restore-partial-two','data-changed-interface','data-changed-source-owner')){
        $dataFile=Join-Path $directory 'data.clixml';$stateFile=Join-Path $directory 'state.clixml';$reportFile=Join-Path $directory 'report.json'
        $data=@{interfaceGuid='test-interface';originalDhcpDisabled=$true
            addresses=@('198.19.240.1','198.19.240.2','198.19.240.3','198.19.240.4')
            originalDefaultKeys=@('5/192.0.2.254/10')}
        if($case -eq 'bad-data'){$data.interfaceGuid='unowned-interface'}
        $data|Export-Clixml -LiteralPath $dataFile
        $twoSources=$case -in @('restore-two','restore-partial-two','changed-second-owner','data-restore-two','data-restore-partial-two')
        $separateData=$case.StartsWith('data-')
        $unusedGuid='11111111-2222-3333-4444-555555555555'
        $fixture=@{removes=0;policyWrites=0;bindingEnabled=($case -ne 'data-restore-disabled');enables=0
            allowedSources=@('198.19.0.1');addresses=[Collections.Generic.List[object]]::new()
            routes=[Collections.Generic.List[object]]::new()}
        if($twoSources){$fixture.allowedSources+='198.19.0.2'}
        $fixture.addresses.Add([pscustomobject]@{IPAddress='198.19.240.1';PrefixLength=29;SkipAsSource=$true;InterfaceIndex=5})
        if($separateData){$fixture.addresses.Add([pscustomobject]@{IPAddress='198.19.255.254';PrefixLength=32;SkipAsSource=$true;InterfaceIndex=9})}
        $fixture.routes.Add([pscustomobject]@{DestinationPrefix='0.0.0.0/0';NextHop='192.0.2.254';RouteMetric=10;InterfaceIndex=5})
        if($case -eq 'changed-default'){$fixture.routes[0].NextHop='192.0.2.253'}
        $restore=$case -notin @('bad-data','overlap-route','overlap-address')
        if($restore){
            $saved=@{interfaceGuid='test-interface';source='198.19.0.1';prefix='198.19.0.0/17';originalAbsent=$true
                originalAddresses=@('198.19.240.1/29/True')}
            if($twoSources){$saved.sources=$fixture.allowedSources}
            if($separateData){
                $saved.interfaceGuid=$unusedGuid;$saved.detachInterface=$true
                $saved.originalAddresses=@('198.19.255.254/32/True')
                $saved.populationInterfaceGuid='test-interface'
                $saved.populationOriginalAddresses=@('198.19.240.1/29/True')
            }
            $saved|Export-Clixml -LiteralPath $stateFile
        }
        if($separateData -or $case -in @('restore','changed-owner','changed-prefix','remove-failure','overlap-address','restore-two','restore-partial-two','changed-second-owner')){
            $index=if($case -in @('changed-owner','data-changed-source-owner')){6}else{5}
            $bits=if($case -eq 'changed-prefix'){24}else{17}
            $fixture.addresses.Add([pscustomobject]@{IPAddress='198.19.0.1';PrefixLength=$bits;SkipAsSource=$true;InterfaceIndex=$index})
            $fixture.routes.Add([pscustomobject]@{DestinationPrefix='198.19.0.0/17';NextHop='0.0.0.0';RouteMetric=256;InterfaceIndex=5})
        }
        if($case -in @('restore-two','changed-second-owner','data-restore-two')){
            $fixture.addresses.Add([pscustomobject]@{IPAddress='198.19.0.2';PrefixLength=17;SkipAsSource=$true
                InterfaceIndex=$(if($case -eq 'changed-second-owner'){6}else{5})})
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
                    if($separateData -and $Name -ne 'test-data-interface'){
                        return [pscustomobject]@{InterfaceGuid=$unusedGuid;ifIndex=9}
                    }
                    if($case -eq 'data-changed-interface'){return [pscustomobject]@{InterfaceGuid='changed-interface';ifIndex=5}}
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
                    foreach($index in @(5,9)){
                        if(-not $PSBoundParameters.ContainsKey('InterfaceIndex') -or $InterfaceIndex -eq $index){
                            [pscustomobject]@{Dhcp='Disabled';InterfaceIndex=$index}
                        }
                    }
                }
                function Get-NetAdapterBinding {
                    [CmdletBinding()]param($Name,$ComponentID)
                    if(-not $separateData -or $Name -ne 'NetperfPath-abcdef123456' -or $ComponentID -ne 'ms_tcpip'){
                        throw 'An unowned binding query was attempted.'
                    }
                    [pscustomobject]@{Enabled=$fixture.bindingEnabled}
                }
                function Enable-NetAdapterBinding {
                    [CmdletBinding(SupportsShouldProcess=$true)]param($Name,$ComponentID)
                    if(-not $separateData -or $Name -ne 'NetperfPath-abcdef123456' -or $ComponentID -ne 'ms_tcpip'){
                        throw 'An unowned binding restoration was attempted.'
                    }
                    $fixture.enables++;$fixture.bindingEnabled=$true
                }
                function Set-NetIPInterface {
                    [CmdletBinding()]param($InterfaceIndex,$AddressFamily,$Dhcp)
                    if(-not $separateData -or $InterfaceIndex -ne 9 -or $Dhcp -ne 'Disabled'){
                        throw 'An unowned policy change was attempted.'
                    }
                    $fixture.policyWrites++
                }
                function Remove-NetIPAddress {
                    [CmdletBinding(SupportsShouldProcess=$true)]
                    param($InterfaceIndex,$IPAddress,$PolicyStore)
                    if($InterfaceIndex -ne 5 -or $IPAddress -notin $fixture.allowedSources -or $PolicyStore -ne 'ActiveStore'){
                        throw 'An unowned address removal was attempted.'
                    }
                    $fixture.removes++
                    if($case -eq 'remove-failure'){throw 'Synthetic removal failure.'}
                    foreach($entry in @($fixture.addresses|Where-Object IPAddress -eq $IPAddress)){$null=$fixture.addresses.Remove($entry)}
                    if(-not @($fixture.addresses|Where-Object{$_.IPAddress -in $fixture.allowedSources}).Count){
                        foreach($entry in @($fixture.routes|Where-Object DestinationPrefix -eq '198.19.0.0/17')){$null=$fixture.routes.Remove($entry)}
                    }
                }
                function New-NetIPAddress {throw 'Preflight tests must never mutate addresses.'}
                $extra=if($restore){@{RestoreOnly=$true}}else{@{ReadyFile='unused';BeginFile='unused';StopFile='unused'}}
                if($twoSources){$extra.PathCount=49152}
                if($separateData){$extra.UnusedInterfaceGuid=$unusedGuid;$extra.PopulationInterfaceAlias='test-data-interface'}
                $alias=if($separateData){'NetperfPath-abcdef123456'}else{'test-only-interface'}
                & $program -InterfaceAlias $alias -DataStateFile $dataFile -StateFile $stateFile -ReportFile $reportFile @extra
            }
        }catch{
            $pattern=switch($case){
                bad-data {'requires owned receiver addresses'}
                changed-owner {'changed ownership'}
                changed-second-owner {'changed ownership'}
                data-changed-interface {'must remain on the verified data interface'}
                data-changed-source-owner {'changed ownership'}
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
        if($failed -ne ($case -notin @('restore','already-absent','restore-two','restore-partial-two','data-restore','data-restore-disabled','data-restore-two','data-restore-partial-two'))){throw "Unexpected retirement verdict: $case"}
        if($case -in @('bad-data','changed-owner','changed-prefix','overlap-route','overlap-address','changed-second-owner','data-changed-interface','data-changed-source-owner') -and
            ($fixture.removes -or $fixture.policyWrites -or $fixture.enables)){
            throw 'Rejected ownership or overlap mutated state.'
        }
        if($case -in @('restore','restore-two','restore-partial-two') -and
            ($fixture.removes -ne $(if($case -eq 'restore-two'){2}else{1}) -or $fixture.addresses.Count -ne 1)){
            throw 'The owned source was not exclusively retired.'
        }
        if($case -in @('data-restore','data-restore-disabled','data-restore-two','data-restore-partial-two') -and
            ($fixture.removes -ne $(if($case -eq 'data-restore-two'){2}else{1}) -or
                $fixture.addresses.Count -ne 2 -or $fixture.policyWrites -ne 1 -or
                $fixture.enables -ne $(if($case -eq 'data-restore-disabled'){1}else{0}))){
            throw 'Separate cache cleanup changed data/bootstrap ownership or policy.'
        }
        foreach($file in @($dataFile,$stateFile,$reportFile)){if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file}}
        $checks++
    }
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($program,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ($errors|Out-String)}
    $body=@($ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.TryStatementAst] -and
            $node.Body.Extent.Text.Contains('$report.populationMilliseconds=')
    },$true))
    if($body.Count -ne 1){throw 'The actual cache-population lifecycle must be unique.'}
    $statements=@($body[0].Body.Statements)
    & {
        $sources=@('198.19.0.1','198.19.0.2')
        $populationAdapter=@([pscustomobject]@{ifIndex=5})
        $adapter=@([pscustomobject]@{ifIndex=9})
        $writes=[Collections.Generic.List[string]]::new()
        function New-NetIPAddress {
            [CmdletBinding()]param($InterfaceIndex,$IPAddress,$PrefixLength,$SkipAsSource,$PolicyStore)
            if($InterfaceIndex -ne 5 -or $IPAddress -notin $sources -or $PrefixLength -ne 17 -or
                -not $SkipAsSource -or $PolicyStore -ne 'ActiveStore'){throw 'Cache population targeted the retired or unowned interface.'}
            $writes.Add($IPAddress)
        }
        & ([scriptblock]::Create($statements[0].Extent.Text))
        if($writes.Count -ne 2){throw 'The actual population lifecycle did not create both owned data sources.'}
    }
    $checks++
    $first=@($statements|Where-Object{$_.Extent.Text -eq '$report.measuredHeldPaths=Read-PathCount'})
    $last=@($statements|Where-Object{$_.Extent.Text.StartsWith('$report.applyStartUtc=')})
    if($first.Count -ne 1 -or $last.Count -ne 1){throw 'The actual socket-release lifecycle boundaries must be unique.'}
    $lifecycle=($statements|Where-Object{
        $_.Extent.StartOffset -ge $first[0].Extent.StartOffset -and $_.Extent.StartOffset -lt $last[0].Extent.StartOffset
    }|ForEach-Object{$_.Extent.Text})-join "`n"
    Add-Type -TypeDefinition @'
using System;
using System.Collections;
using System.IO;
public static class ArrivalTcp {
    public static string ReadyPath;
    public static bool ExpectedReady;
    public static int Releases;
    public static int CountEstablishedConnections(int processId, int port) { return 16; }
    public static void ReleaseIdlePathSockets(IList sockets) {
        if (File.Exists(ReadyPath) != ExpectedReady || sockets.Count != 1)
            throw new InvalidOperationException("The real lifecycle released sockets in the wrong phase.");
        Releases++;
    }
}
'@
    foreach($phase in @('start','end','end-too-early','during')){
        & {
            $ReadyFile=Join-Path $directory 'ready';$BeginFile=Join-Path $directory 'begin'
            $EndFile=if($phase -ne 'start'){Join-Path $directory 'end'}else{''}
            $StopFile=Join-Path $directory 'stop';$PathCount=1024
            [IO.File]::WriteAllText($BeginFile,'pre-collection-call')
            $sockets=[Collections.ArrayList]::new();$null=$sockets.Add([object]::new())
            $report=[ordered]@{};$fixture=@{Reads=0;Signals=[Collections.Generic.List[string]]::new()}
            $ReceiverProcessId=42
            $RetireDuringGc=$phase -eq 'during'
            $pathTiming=@{QueryMilliseconds=0;RowScanMilliseconds=0}
            $wait=[Diagnostics.Stopwatch]::StartNew()
            [ArrivalTcp]::ReadyPath=$ReadyFile;[ArrivalTcp]::ExpectedReady=($phase -eq 'start');[ArrivalTcp]::Releases=0
            function Read-PathCount {
                $fixture.Reads++
                if($phase -ne 'start' -and $fixture.Reads -eq 2 -and
                    ($sockets.Count -ne 0 -or (Test-Path -LiteralPath $ReadyFile))){
                    throw 'Pre-released cached paths must verify before traffic readiness.'
                }
                $PathCount
            }
            function Wait-ControlSignal {
                param($File,$PollMilliseconds=5)
                $fixture.Signals.Add($File)
                if(-not(Test-Path -LiteralPath $ReadyFile)){throw 'Signals must never be awaited before traffic readiness.'}
                if($phase -eq 'end-too-early' -and $File -eq $BeginFile){
                    [IO.File]::WriteAllText($EndFile,'gc-completed-before-validation')
                }
                if($File -eq $EndFile){
                    if($report.establishedAtSnapshot -ne 16 -or -not $report.snapshotCompletedUtc){
                        throw 'Cache and cohort verification must finish before the GC-completion wait.'
                    }
                    [IO.File]::WriteAllText($EndFile,'actual-completed-gc')
                }
            }
            $rejected=$false
            try{& ([scriptblock]::Create($lifecycle))}catch{
                if($phase -ne 'end-too-early' -or $_.Exception.Message -notmatch 'GC completed before cache and cohort verification'){throw}
                $rejected=$true
            }
            if($rejected -ne ($phase -eq 'end-too-early')){throw 'An unaligned completed-GC snapshot was not rejected.'}
            if([ArrivalTcp]::Releases -ne 1 -or $sockets.Count -ne 0 -or
                $report.measuredReleasedPaths -ne $PathCount -or
                $fixture.Reads -ne $(if($phase -ne 'start'){3}else{2}) -or
                $fixture.Signals.Count -ne $(if($phase -eq 'end'){2}else{1}) -or
                $fixture.Signals[0] -ne $BeginFile -or
                -not (Test-Path -LiteralPath $ReadyFile)){
                throw 'The real retirement lifecycle did not preserve release/readiness/count verification.'
            }
        }
        foreach($name in @('ready','begin','end')){
            $file=Join-Path $directory $name
            if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file}
        }
        $checks++
    }
    Write-Host "Passed $checks source-retirement ownership, restoration and actual socket-release lifecycle cases; no network operations were performed."
}finally{
    foreach($name in @('data.clixml','state.clixml','report.json','ready','begin','end')){
        $file=Join-Path $directory $name
        if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file}
    }
    Remove-Item -LiteralPath $directory -ErrorAction Stop
}
