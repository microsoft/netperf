# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TcpStateFile,
    [Parameter(Mandatory)][string]$ClrStateFile,
    [Parameter(Mandatory)][string]$Output,
    [string]$KernelOutput,
    [ValidateSet('SpinWithScheduling','SampledOnly','SpinWithoutScheduling')][string]$KernelMode='SpinWithScheduling'
)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh WPR profile output.'}
if($KernelMode -ne 'SpinWithScheduling' -and -not $KernelOutput){throw 'A focused kernel mode requires an explicit exported kernel profile.'}
if($KernelOutput){
    if(Test-Path -LiteralPath $KernelOutput){throw 'Use a fresh kernel WPR profile output.'}
    & "$env:SystemRoot\System32\wpr.exe" -exportprofile CPU $KernelOutput -filemode
    if($LASTEXITCODE){throw 'Cannot export the installed CPU profile for owned kernel capture.'}
    [xml]$kernel=Get-Content -LiteralPath $KernelOutput -Raw
    $systems=@($kernel.WindowsPerformanceRecorder.Profiles.SystemProvider|
        Where-Object{'SampledProfile' -in @($_.Keywords.Keyword.Value)})
    if($systems.Count -ne 1){throw 'The installed sampled CPU system provider is not unique.'}
    if($KernelMode -ne 'SpinWithScheduling'){
        foreach($node in @($systems[0].Keywords.Keyword|Where-Object{$_.Value -notin @('CpuConfig','Loader','ProcessThread','SampledProfile')})){
            $null=$node.ParentNode.RemoveChild($node)
        }
        foreach($node in @($systems[0].Stacks.Stack|Where-Object{$_.Value -in @('CSwitch','ReadyThread')})){
            $null=$node.ParentNode.RemoveChild($node)
        }
        foreach($node in @($kernel.SelectNodes('//Profile/Collectors/EventCollectorId'))){$null=$node.ParentNode.RemoveChild($node)}
        foreach($node in @($kernel.SelectNodes('/WindowsPerformanceRecorder/Profiles/EventCollector|/WindowsPerformanceRecorder/Profiles/EventProvider'))){
            $null=$node.ParentNode.RemoveChild($node)
        }
    }
    if($KernelMode -ne 'SampledOnly'){
        $spin=$kernel.CreateElement('Keyword');$spin.SetAttribute('Value','SpinLock');$spin.SetAttribute('Strict','true')
        $null=$systems[0].Keywords.AppendChild($spin)
    }
    foreach($collector in @($kernel.WindowsPerformanceRecorder.Profiles.SystemCollector)){
        $collector.BufferSize.SetAttribute('Value','1024')
        $collector.Buffers.SetAttribute('Value','256')
    }
    $kernel.Save($KernelOutput)
}
$definitions=[Collections.Generic.List[string]]::new()
foreach($entry in @(@{Id='Tcp';Path=$TcpStateFile},@{Id='Clr';Path=$ClrStateFile})){
    $state=Get-Content -LiteralPath $entry.Path -Raw|ConvertFrom-Json
    $guid=[guid]::Parse($state.publicProviderGuid).ToString('D')
    $keywords=[string]$state.publicProviderKeywords
    if($keywords -notmatch '^0x[0-9a-fA-F]{1,16}$' -or [Convert]::ToUInt64($keywords.Substring(2),16) -eq 0){
        throw 'Exact WPR probes require explicit nonzero public provider keywords.'
    }
    $ids=@($state.publicProviderEvents|ForEach-Object{
        $id=[int]$_.Id
        if($id -lt 1 -or $id -gt 65535){throw 'Public event IDs must be positive 16-bit integers.'}
        $id
    }|Sort-Object -Unique)
    if($ids.Count -lt 1 -or $ids.Count -gt 16){throw 'Each provider requires one to sixteen distinct public event IDs.'}
    $filters=($ids|ForEach-Object{'<EventId Value="{0}" />' -f $_}) -join ''
    $nonPaged=if($entry.Id -eq 'Tcp'){' NonPagedMemory="true"'}else{''}
    $definitions.Add(('<EventProvider Id="{0}" Name="{1}" Level="5" Strict="true"{4}><Keywords><Keyword Value="{3}" /></Keywords><EventFilters FilterIn="true">{2}</EventFilters></EventProvider>' -f $entry.Id,$guid,$filters,$keywords,$nonPaged))
}
$xml=@"
<?xml version="1.0" encoding="utf-8"?>
<WindowsPerformanceRecorder Version="1.0" Author="Microsoft">
  <Profiles>
    <EventCollector Id="GcEvents" Name="TcpChurn GC Events">
      <BufferSize Value="64" />
      <Buffers Value="1024" />
    </EventCollector>
    $($definitions -join "`n")
    <Profile Id="GcProbeEvents.Verbose.File" Name="GcProbeEvents" Description="Exact public TCP and CLR events" LoggingMode="File" DetailLevel="Verbose">
      <Collectors>
        <EventCollectorId Value="GcEvents">
          <EventProviders><EventProviderId Value="Tcp" /><EventProviderId Value="Clr" /></EventProviders>
        </EventCollectorId>
      </Collectors>
    </Profile>
  </Profiles>
</WindowsPerformanceRecorder>
"@
[IO.File]::WriteAllText($Output,$xml,[Text.UTF8Encoding]::new($false))
