# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
param([ValidateSet('arrays','graph')][string]$HeapLayout='arrays')
$ErrorActionPreference='Stop'
$directory=Join-Path ([IO.Path]::GetTempPath()) ('server-gc-arrival-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $directory
$exe=Join-Path $directory 'ArrivalTcp.exe'
$children=[Collections.Generic.List[object]]::new()
function Start-Child([string[]]$Arguments) {
    $info=[Diagnostics.ProcessStartInfo]::new()
    $info.FileName=$exe;$info.UseShellExecute=$false;$info.RedirectStandardError=$true
    foreach($argument in $Arguments){$info.ArgumentList.Add($argument)}
    $process=[Diagnostics.Process]::Start($info)
    $child=@{process=$process;error=$process.StandardError.ReadToEndAsync()}
    $children.Add($child)
    $child
}
try {
    & "$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:exe /platform:x64 "/out:$exe" (Join-Path $PSScriptRoot 'ArrivalTcp.cs')
    if($LASTEXITCODE){throw 'Server-GC helper compilation failed.'}
    Copy-Item (Join-Path $PSScriptRoot 'ArrivalTcp.ServerGc.config') ($exe+'.config')
    $probe=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Parse('127.0.0.2'),0)
    $probe.Start();$port=$probe.LocalEndpoint.Port;$probe.Stop()
    $serverOutput=Join-Path $directory 'server.json'
    $server=Start-Child @('127.0.0.1','127.0.0.2',[string]$port,'128','4000','65536',
        $serverOutput,'server','262144','14529','64','nodelay',("gc:32:32:{0}" -f $HeapLayout))
    $wait=[Diagnostics.Stopwatch]::StartNew()
    while(-not(Test-Path ($serverOutput+'.ready'))) {
        if($server.process.HasExited -or $wait.Elapsed.TotalSeconds -gt 15){throw 'The GC receiver did not become ready.'}
        Start-Sleep -Milliseconds 20
    }
    $first=Start-Child @('127.0.0.1','127.0.0.2',[string]$port,'64','2000','65536',
        (Join-Path $directory 'first.json'),'client','262144','14529','64','nodelay','dispatch:pool')
    $second=Start-Child @('127.0.0.4','127.0.0.2',[string]$port,'64','2000','65536',
        (Join-Path $directory 'second.json'),'client','262144','23521','64','nodelay','dispatch:pool')
    foreach($child in @($first,$second,$server)) {
        if(-not $child.process.WaitForExit(30000)){throw 'An independent server-GC endpoint exceeded its deadline.'}
        if($child.process.ExitCode -ne 0){throw "An independent server-GC endpoint failed: $($child.error.GetAwaiter().GetResult())"}
    }
    $r=Get-Content $serverOutput -Raw|ConvertFrom-Json
    $a=Get-Content (Join-Path $directory 'first.json') -Raw|ConvertFrom-Json
    $b=Get-Content (Join-Path $directory 'second.json') -Raw|ConvertFrom-Json
    foreach($client in @($a,$b)) {
        if($client.outcome -ne 'collected' -or $client.connections -ne 64 -or $client.bytesSent -ne 4MB -or
            $client.bytesReceived -ne 16MB -or $client.managedGc.enabled -or $client.arrivalDispatch -ne 'thread-pool' -or $client.barrier){
            throw 'An independent arrival producer was paused, corrupted data, or used a barrier.'
        }
    }
    if($r.outcome -ne 'collected' -or $r.connections -ne 128 -or $r.bytesReceived -ne $a.bytesSent+$b.bytesSent -or
        $r.bytesSent -ne $a.bytesReceived+$b.bytesReceived -or $r.requestDispatch -ne 'thread-pool' -or
        $r.peakInFlight -lt 1 -or $r.peakInFlight -gt 64 -or $r.barrier){
        throw 'Receiver dispatch, capacity, or endpoint byte accounting failed.'
    }
    $gc=$r.managedGc
    if(-not $gc.enabled -or -not $gc.serverGc -or $gc.heapMiB -ne 32 -or $gc.heapLayout -ne $HeapLayout -or
        $gc.gen2CollectionsAfter -le $gc.gen2CollectionsBefore -or $gc.blockingCollectionMilliseconds -le 0 -or
        $gc.completedBeforeCollection -lt 1 -or $gc.inFlightBeforeCollection -lt 1 -or $gc.launchedAtCollection -lt 32){
        throw 'A real receiver GC did not overlap completed and in-flight requests.'
    }
}finally {
    foreach($child in $children) {
        if(-not $child.process.HasExited){Stop-Process -Id $child.process.Id -Force -ErrorAction Stop}
        if(-not $child.process.WaitForExit(5000)){throw 'An owned server-GC endpoint remained.'}
        $child.process.Dispose()
    }
    foreach($file in @('ArrivalTcp.exe','ArrivalTcp.exe.config','server.json','server.json.ready','first.json','second.json')) {
        $path=Join-Path $directory $file
        if(Test-Path $path){Remove-Item -LiteralPath $path -ErrorAction Stop}
    }
    Remove-Item -LiteralPath $directory -ErrorAction Stop
}
Write-Output 'Passed independent-producer receiver-GC integrity, bounded dispatch and real-GC overlap checks; not performance evidence.'
