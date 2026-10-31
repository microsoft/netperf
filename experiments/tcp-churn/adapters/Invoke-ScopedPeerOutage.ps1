# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Addresses,
    [Parameter(Mandatory)][ValidateRange(1000,30000)][int]$DelayMilliseconds,
    [Parameter(Mandatory)][ValidateRange(500,6000)][int]$DurationMilliseconds,
    [Parameter(Mandatory)][string]$ReadyFile,
    [Parameter(Mandatory)][string]$StopFile,
    [Parameter(Mandatory)][string]$ReportFile,
    [Parameter(Mandatory)][ValidatePattern('^NetperfClusterOutage-[0-9a-f]{32}$')][string]$RuleName
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$plan=@($Addresses.Split(','))
if($plan.Count -lt 1 -or $plan.Count -gt 500 -or @($plan|Sort-Object -Unique).Count -ne $plan.Count){
    throw 'One to five hundred unique outage addresses are required.'
}
foreach($address in $plan){
    if($address -notmatch '^198\.19\.6[4-7]\.\d{1,3}$'){throw 'The outage is limited to the owned cluster prefix.'}
    if(@(Get-NetIPAddress -IPAddress $address -AddressFamily IPv4 -ErrorAction SilentlyContinue).Count -ne 1){
        throw 'Every outage address must be an owned local cluster address.'
    }
}
if(@(Get-NetFirewallRule -Name $RuleName -PolicyStore ActiveStore -ErrorAction SilentlyContinue).Count){
    throw 'The owned outage rule name is already in use.'
}
$rule=$RuleName
$report=[ordered]@{schema=1;scope='owned-cluster-addresses-inbound-silent-drop';affectedAddresses=$plan.Count
    requestedDelayMilliseconds=$DelayMilliseconds;requestedDurationMilliseconds=$DurationMilliseconds
    applied=$false;removed=$false;stoppedBeforeOutage=$false}
$failure=$null
try{
    [IO.File]::WriteAllText($ReadyFile,'ready')
    $clock=[Diagnostics.Stopwatch]::StartNew()
    while($clock.ElapsedMilliseconds -lt $DelayMilliseconds){
        if(Test-Path -LiteralPath $StopFile){$report.stoppedBeforeOutage=$true;break}
        Start-Sleep -Milliseconds 20
    }
    if(-not $report.stoppedBeforeOutage){
        $report.outageStartUtc=[DateTime]::UtcNow.ToString('o')
        $null=New-NetFirewallRule -Name $rule -DisplayName $rule -Direction Inbound -Action Block -Protocol TCP `
            -LocalAddress $plan -PolicyStore ActiveStore -ErrorAction Stop
        $report.applied=$true
        $report.outageAppliedUtc=[DateTime]::UtcNow.ToString('o')
        $hold=[Diagnostics.Stopwatch]::StartNew()
        while($hold.ElapsedMilliseconds -lt $DurationMilliseconds){Start-Sleep -Milliseconds 10}
    }
}catch{$failure=$_}
finally{
    try{
        if(@(Get-NetFirewallRule -Name $rule -PolicyStore ActiveStore -ErrorAction SilentlyContinue).Count){
            Remove-NetFirewallRule -Name $rule -PolicyStore ActiveStore -ErrorAction Stop
            $report.outageRemovedUtc=[DateTime]::UtcNow.ToString('o')
        }
        if(@(Get-NetFirewallRule -Name $rule -PolicyStore ActiveStore -ErrorAction SilentlyContinue).Count){
            throw 'The owned outage rule remains.'
        }
        $report.removed=$true
    }catch{
        $report.removed=$false
        if($null -eq $failure){$failure=$_}
    }
    $report.outcome=if($null -eq $failure){'completed'}else{'failed'}
    if($null -ne $failure){$report.failureType=$failure.Exception.GetType().FullName}
    $report|ConvertTo-Json|Set-Content -LiteralPath $ReportFile
}
if($null -ne $failure){throw $failure}
