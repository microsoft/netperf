# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
$ErrorActionPreference='Stop'
$directory=Join-Path ([IO.Path]::GetTempPath()) ('gc-wpr-profile-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $directory
try{
    $tcp=Join-Path $directory 'tcp.json';$clr=Join-Path $directory 'clr.json';$profile=Join-Path $directory 'probes.wprp'
    @{publicProviderGuid='2f07e2ee-15db-40f1-90ef-9d7ba282188a';publicProviderEvents=@(@{Id=100},@{Id=101},@{Id=100})}|
        ConvertTo-Json -Depth 4|Set-Content -LiteralPath $tcp
    @{publicProviderGuid='e13c0d23-ccbc-4e12-931b-d9cc2eee27e4';publicProviderEvents=@(@{Id=1},@{Id=2},@{Id=9})}|
        ConvertTo-Json -Depth 4|Set-Content -LiteralPath $clr
    $program=Join-Path $PSScriptRoot 'adapters\New-GcProbeWprProfile.ps1'
    & $program -TcpStateFile $tcp -ClrStateFile $clr -Output $profile
    [xml]$xml=Get-Content -LiteralPath $profile -Raw
    $providers=@($xml.WindowsPerformanceRecorder.Profiles.EventProvider)
    if($providers.Count -ne 2 -or $providers[0].Strict -ne 'true' -or
        (@($providers[0].EventFilters.EventId.Value)-join ',') -ne '100,101' -or
        (@($providers[1].EventFilters.EventId.Value)-join ',') -ne '1,2,9'){
        throw 'The WPR profile did not preserve the exact public provider/event filters.'
    }
    & "$env:SystemRoot\System32\wpr.exe" -profiles $profile
    if($LASTEXITCODE){throw 'The installed WPR rejected the generated schema.'}
    Remove-Item -LiteralPath $profile
    @{publicProviderGuid='2f07e2ee-15db-40f1-90ef-9d7ba282188a';publicProviderEvents=@(@{Id=65536})}|
        ConvertTo-Json -Depth 4|Set-Content -LiteralPath $tcp
    $rejected=$false
    try{& $program -TcpStateFile $tcp -ClrStateFile $clr -Output $profile}catch{
        if($_.Exception.Message -notmatch 'positive 16-bit'){throw}
        $rejected=$true
    }
    if(-not $rejected -or (Test-Path -LiteralPath $profile)){throw 'Invalid public event IDs produced a WPR profile.'}
    Write-Output 'Passed exact-event WPR schema and invalid-ID checks; no recording was started.'
}finally{
    foreach($name in @('tcp.json','clr.json','probes.wprp')){
        $file=Join-Path $directory $name
        if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file}
    }
    Remove-Item -LiteralPath $directory
}
