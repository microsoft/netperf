# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function ConvertTo-RssProcessorKey($Processor) {
    if($Processor -is [string]) {
        if($Processor -notmatch '^(?<group>[0-9]{1,5}):(?<number>[0-9]{1,2})(?:/[0-9]{1,5})?$') {
            throw 'Unknown RSS processor string representation.'
        }
        $group=[int]$Matches.group;$number=[int]$Matches.number
    } elseif($null -ne $Processor -and $null -ne $Processor.PSObject.Properties['ProcessorGroup'] -and
        $null -ne $Processor.PSObject.Properties['ProcessorNumber']) {
        $group=$Processor.ProcessorGroup;$number=$Processor.ProcessorNumber
    } elseif($null -ne $Processor -and $null -ne $Processor.PSObject.Properties['Group'] -and
        $null -ne $Processor.PSObject.Properties['Number']) {
        $group=$Processor.Group;$number=$Processor.Number
    } else { throw 'Unknown RSS processor object representation.' }
    if([string]$group -notmatch '^[0-9]{1,5}$' -or [string]$number -notmatch '^[0-9]{1,2}$') {
        throw 'RSS processor coordinates must be non-null unsigned integers.'
    }
    $group=[int]$group;$number=[int]$number
    if($group -lt 0 -or $group -gt 65535 -or $number -lt 0 -or $number -gt 63) {
        throw 'RSS processor number is outside its group-relative range.'
    }
    "${group}:$number"
}

function Assert-RssControlPath {
    param(
        [Parameter(Mandatory)]$Settings,
        [ValidateSet(1,2,4,8,16,32,64,128)][int]$ExpectedProcessors=128,
        [ValidateSet(1,2,4,8,16,32,64,128)][int]$ExpectedQueues=128
    )
    if($Settings.Enabled -ne $true) { throw 'RSS is not enabled.' }
    if($Settings.NumberOfReceiveQueues -ne $ExpectedQueues -or $Settings.MaxProcessors -ne $ExpectedProcessors) {
        throw 'Effective queue or maximum-processor configuration does not match the request.'
    }
    $processors=@($Settings.RssProcessorArray)
    $table=@($Settings.IndirectionTable)
    if($processors.Count -ne $Settings.RssProcessorArraySize -or $table.Count -ne $Settings.IndirectionTableEntryCount) {
        throw 'RSS array metadata differs from the returned arrays.'
    }
    $eligible=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($processor in $processors) {
        if(-not $eligible.Add((ConvertTo-RssProcessorKey $processor))) { throw 'Duplicate RSS processor-array entry.' }
    }
    if($eligible.Count -ne $ExpectedProcessors) { throw 'The effective RSS processor array does not cover the requested processor count.' }
    $assigned=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($processor in $table) {
        $key=ConvertTo-RssProcessorKey $processor
        if(-not $eligible.Contains($key)) { throw 'Indirection-table target is outside the RSS processor array.' }
        $null=$assigned.Add($key)
    }
    if($assigned.Count -ne $ExpectedProcessors) { throw 'The indirection table does not assign every requested RSS processor.' }
    $groups=@($assigned|ForEach-Object{[int]($_.Split(':')[0])}|Sort-Object -Unique)
    [pscustomobject][ordered]@{
        schema=1;expectedProcessors=$ExpectedProcessors;receiveQueues=[int]$Settings.NumberOfReceiveQueues
        rssProcessors=$eligible.Count;indirectionEntries=$table.Count;distinctAssignedProcessors=$assigned.Count
        processorGroups=$groups;controlPathVerified=$true;adapterConfigurationChanged=$false
        runtimeDpcCoverageVerified=$false;performanceVerified=$false;conclusion='rss-control-path-only'
    }
}
Export-ModuleMember -Function Assert-RssControlPath
