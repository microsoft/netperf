# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TcpStateFile,
    [Parameter(Mandatory)][string]$ClrStateFile,
    [Parameter(Mandatory)][string]$Output
)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh WPR profile output.'}
$definitions=[Collections.Generic.List[string]]::new()
foreach($entry in @(@{Id='Tcp';Path=$TcpStateFile},@{Id='Clr';Path=$ClrStateFile})){
    $state=Get-Content -LiteralPath $entry.Path -Raw|ConvertFrom-Json
    $guid=[guid]::Parse($state.publicProviderGuid).ToString('D')
    $ids=@($state.publicProviderEvents|ForEach-Object{
        $id=[int]$_.Id
        if($id -lt 1 -or $id -gt 65535){throw 'Public event IDs must be positive 16-bit integers.'}
        $id
    }|Sort-Object -Unique)
    if($ids.Count -lt 1 -or $ids.Count -gt 16){throw 'Each provider requires one to sixteen distinct public event IDs.'}
    $filters=($ids|ForEach-Object{'<EventId Value="{0}" />' -f $_}) -join ''
    $definitions.Add(('<EventProvider Id="{0}" Name="{1}" Level="5" Strict="true"><Keywords><Keyword Value="0xffffffffffffffff" /></Keywords><EventFilters FilterIn="true">{2}</EventFilters></EventProvider>' -f $entry.Id,$guid,$filters))
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
