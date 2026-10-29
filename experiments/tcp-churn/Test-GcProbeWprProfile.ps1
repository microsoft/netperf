# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
param([switch]$CaptureSmoke,[switch]$CaptureSpinLocks)
$ErrorActionPreference='Stop'
$directory=Join-Path ([IO.Path]::GetTempPath()) ('gc-wpr-profile-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $directory
try{
    $tcp=Join-Path $directory 'tcp.json';$clr=Join-Path $directory 'clr.json';$profile=Join-Path $directory 'probes.wprp'
    @{publicProviderGuid='2f07e2ee-15db-40f1-90ef-9d7ba282188a';publicProviderKeywords='0x500000084';publicProviderEvents=@(@{Id=1004},@{Id=1017},@{Id=1004})}|
        ConvertTo-Json -Depth 4|Set-Content -LiteralPath $tcp
    @{publicProviderGuid='e13c0d23-ccbc-4e12-931b-d9cc2eee27e4';publicProviderKeywords='0x1';publicProviderEvents=@(@{Id=1},@{Id=2},@{Id=9})}|
        ConvertTo-Json -Depth 4|Set-Content -LiteralPath $clr
    $program=Join-Path $PSScriptRoot 'adapters\New-GcProbeWprProfile.ps1'
    $profileArguments=@{TcpStateFile=$tcp;ClrStateFile=$clr;Output=$profile}
    $kernelProfile=Join-Path $directory 'kernel.wprp'
    if($CaptureSpinLocks){$profileArguments.KernelOutput=$kernelProfile}
    & $program @profileArguments
    [xml]$xml=Get-Content -LiteralPath $profile -Raw
    $providers=@($xml.WindowsPerformanceRecorder.Profiles.EventProvider)
    if($providers.Count -ne 2 -or $providers[0].Strict -ne 'true' -or $providers[0].NonPagedMemory -ne 'true' -or
        $providers[0].Keywords.Keyword.Value -ne '0x500000084' -or $providers[1].Keywords.Keyword.Value -ne '0x1' -or
        (@($providers[0].EventFilters.EventId.Value)-join ',') -ne '1004,1017' -or
        (@($providers[1].EventFilters.EventId.Value)-join ',') -ne '1,2,9'){
        throw 'The WPR profile did not preserve the exact public provider/event filters.'
    }
    & "$env:SystemRoot\System32\wpr.exe" -profiles $profile
    if($LASTEXITCODE){throw 'The installed WPR rejected the generated schema.'}
    if($CaptureSpinLocks){
        [xml]$kernel=Get-Content -LiteralPath $kernelProfile -Raw
        $spin=@($kernel.SelectNodes("//SystemProvider/Keywords/Keyword[@Value='SpinLock' and @Strict='true']"))
        if($spin.Count -ne 1){throw 'The exported CPU profile lost its required spinlock keyword.'}
        & "$env:SystemRoot\System32\wpr.exe" -profiles $kernelProfile
        if($LASTEXITCODE){throw 'The installed WPR rejected the owned spinlock profile.'}
    }
    $sampledKernel=Join-Path $directory 'sampled-kernel.wprp'
    & $program -TcpStateFile $tcp -ClrStateFile $clr -Output (Join-Path $directory 'sampled-probes.wprp') `
        -KernelOutput $sampledKernel -KernelMode SampledOnly
    [xml]$sampled=Get-Content -LiteralPath $sampledKernel -Raw
    if(@($sampled.SelectNodes("//SystemProvider/Keywords/Keyword[@Value='CSwitch' or @Value='ReadyThread' or @Value='SpinLock']")).Count -or
        @($sampled.SelectNodes("//SystemProvider/Stacks/Stack[@Value='CSwitch' or @Value='ReadyThread']")).Count -or
        @($sampled.SelectNodes("//SystemProvider/Keywords/Keyword[@Value='SampledProfile']")).Count -ne 1 -or
        @($sampled.SelectNodes("//SystemProvider/Stacks/Stack[@Value='SampledProfile']")).Count -ne 1 -or
        @($sampled.SelectNodes("//SystemProvider/Keywords/Keyword[@Value='Loader']")).Count -ne 1 -or
        @($sampled.SelectNodes("//SystemProvider/Keywords/Keyword[@Value='ProcessThread']")).Count -ne 1 -or
        @($sampled.SelectNodes("//SystemCollector/BufferSize[@Value='1024']")).Count -lt 1 -or
        @($sampled.SelectNodes("//SystemCollector/Buffers[@Value='256']")).Count -lt 1){
        throw 'Focused sampling must retain CPU stacks/module lifetime and bounded buffers, without scheduling or spin event volume.'
    }
    & "$env:SystemRoot\System32\wpr.exe" -profiles $sampledKernel
    if($LASTEXITCODE){throw 'The installed WPR rejected the focused sampling profile.'}
    if($CaptureSmoke){
        $wpr="$env:SystemRoot\System32\wpr.exe"
        $status=@(& $wpr -status)
        if($LASTEXITCODE -ne 0 -or ($status -join "`n") -notmatch 'WPR is not recording'){
            throw 'The dedicated capture-smoke runner already has a recording; refusing interference.'
        }
        $exactExit=$null
        foreach($case in @('tcp-only','clr-only','keyword-only','exact-combined','sampled-combined')){
            [xml]$variant=$xml.OuterXml
            if($case -in @('tcp-only','clr-only')){
                $removeId=if($case -eq 'tcp-only'){'Clr'}else{'Tcp'}
                $node=$variant.SelectSingleNode("/WindowsPerformanceRecorder/Profiles/EventProvider[@Id='$removeId']")
                $null=$node.ParentNode.RemoveChild($node)
                $node=$variant.SelectSingleNode("//EventProviderId[@Value='$removeId']")
                $null=$node.ParentNode.RemoveChild($node)
            }
            if($case -eq 'keyword-only'){
                foreach($node in @($variant.SelectNodes('//EventFilters'))){$null=$node.ParentNode.RemoveChild($node)}
            }
            $variantPath=Join-Path $directory ($case+'.wprp')
            $variant.Save($variantPath)
            $attempted=$false
            try{
                $attempted=$true
                $cpuProfile=if($CaptureSpinLocks){$kernelProfile+'!CPU'}else{'CPU'}
                if($case -eq 'sampled-combined'){$cpuProfile=$sampledKernel+'!CPU'}
                $arguments=if($case -in @('exact-combined','sampled-combined')){@('-start',$cpuProfile,'-start',($variantPath+'!GcProbeEvents'),'-filemode')}
                    else{@('-start',($variantPath+'!GcProbeEvents'),'-filemode')}
                & $wpr @arguments
                $activationExit=$LASTEXITCODE
                Write-Output ("WPR activation case={0} exit=0x{1:X8}" -f $case,$activationExit)
                if($case -eq 'exact-combined'){$exactExit=$activationExit}
                if($case -eq 'sampled-combined' -and $activationExit -ne 0){throw 'Dedicated-runner focused CPU/event activation failed.'}
                if($activationExit -eq 0){
                    Start-Sleep -Milliseconds 250
                    & $wpr -stop (Join-Path $directory ($case+'.etl')) -skipPdbGen
                    if($LASTEXITCODE){throw 'Dedicated-runner recording could not stop.'}
                    $attempted=$false
                }
            }finally{
                if($attempted -and ((@(& $wpr -status)-join "`n") -notmatch 'WPR is not recording')){
                    & $wpr -cancel
                    if($LASTEXITCODE){throw 'The dedicated smoke recording could not be cancelled.'}
                }
            }
        }
        if($exactExit -ne 0){throw 'Dedicated-runner exact-event recording could not start.'}
    }
    Remove-Item -LiteralPath $profile
    @{publicProviderGuid='2f07e2ee-15db-40f1-90ef-9d7ba282188a';publicProviderKeywords='0x500000084';publicProviderEvents=@(@{Id=65536})}|
        ConvertTo-Json -Depth 4|Set-Content -LiteralPath $tcp
    $rejected=$false
    try{& $program -TcpStateFile $tcp -ClrStateFile $clr -Output $profile}catch{
        if($_.Exception.Message -notmatch 'positive 16-bit'){throw}
        $rejected=$true
    }
    if(-not $rejected -or (Test-Path -LiteralPath $profile)){throw 'Invalid public event IDs produced a WPR profile.'}
    Write-Output $(if($CaptureSmoke){'Passed exact-event WPR activation, shutdown, schema and invalid-ID checks.'}
        else{'Passed exact-event WPR schema and invalid-ID checks; no recording was started.'})
}finally{
    foreach($name in @('tcp.json','clr.json','probes.wprp','smoke.etl','kernel.wprp',
        'tcp-only.wprp','tcp-only.etl','clr-only.wprp','clr-only.etl',
        'keyword-only.wprp','keyword-only.etl','exact-combined.wprp','exact-combined.etl',
        'sampled-kernel.wprp','sampled-probes.wprp','sampled-combined.wprp','sampled-combined.etl')){
        $file=Join-Path $directory $name
        if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file}
    }
    Remove-Item -LiteralPath $directory
}
