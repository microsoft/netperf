# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
[CmdletBinding()]
param([string]$Compiler="$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe")
$ErrorActionPreference='Stop'
$directory=Join-Path ([IO.Path]::GetTempPath()) ('arrival-test-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $directory
$exe=Join-Path $directory 'ArrivalTcp.exe'
$output=Join-Path $directory 'result.json'
$child=$null;$server=$null;$checks=0
try {
    & $Compiler /nologo /target:exe /platform:x64 "/out:$exe" (Join-Path $PSScriptRoot 'ArrivalTcp.cs')
    if($LASTEXITCODE){throw 'Arrival helper compilation failed.'}
    $probe=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Parse('127.0.0.2'),0)
    $probe.Start();$port=$probe.LocalEndpoint.Port;$probe.Stop()
    foreach($case in @('valid','existing-output','oversize-count','excess-duration','missing-arguments')) {
        $count=if($case -eq 'oversize-count'){8193}else{16}
        $rate=if($case -eq 'excess-duration'){1}else{128}
        if($case -eq 'excess-duration'){$count=8192}
        $info=[Diagnostics.ProcessStartInfo]::new()
        $info.FileName=$exe;$info.UseShellExecute=$false;$info.RedirectStandardError=$true
        foreach($argument in @('127.0.0.1','127.0.0.2',[string]$port,[string]$count,[string]$rate,'65536',$output)) {
            $info.ArgumentList.Add($argument)
        }
        if($case -eq 'missing-arguments'){$info.ArgumentList.Clear()}
        $child=[Diagnostics.Process]::Start($info)
        $errorText=$child.StandardError.ReadToEndAsync()
        if(-not $child.WaitForExit(10000)){throw 'Arrival test exceeded its deadline.'}
        if(($child.ExitCode -eq 0) -ne ($case -eq 'valid')){throw "Incorrect arrival outcome: ${case}: $($errorText.GetAwaiter().GetResult())"}
        if($case -eq 'missing-arguments' -and ($child.ExitCode -ne 2 -or
            $errorText.GetAwaiter().GetResult() -notmatch '^Usage: ArrivalTcp ')){throw 'Missing arrival arguments did not produce explicit usage.'}
        if($case -eq 'valid') {
            $result=Get-Content -LiteralPath $output -Raw|ConvertFrom-Json
            if($result.connections -ne 16 -or $result.bytesSent -ne 1048576 -or $result.networkErrors -ne 0 -or
                $result.protocolErrors -ne 0 -or $result.barrier -or $result.seed -ne 14529 -or
                $result.launchSpanMilliseconds -le 0 -or $result.meanLaunchLagMilliseconds -lt 0) {
                throw 'Independent-arrival payload, timing or no-barrier contract failed.'
            }
        }
        $child.Dispose();$child=$null;$checks++
    }
    foreach($pacing in @('nodelay','nagle','pipelined-nagle')){
        $rejectedOutput=Join-Path $directory 'rejected-framed.json'
        $info.ArgumentList.Clear()
        $descriptor=if($pacing -eq 'pipelined-nagle'){'servicewait64:pipelined'}elseif($pacing -eq 'nodelay'){'exchanges:64:framed'}else{'exchanges:64:unknown'}
        $payload=if($pacing -eq 'pipelined-nagle'){'512'}else{'1460'}
        $socketPacing=if($pacing -eq 'pipelined-nagle'){'nagle'}else{$pacing}
        $expectedError=if($pacing -eq 'pipelined-nagle'){'Pipelined service requests require'}else{'Framed exchanges require'}
        foreach($argument in @('127.0.0.1','127.0.0.2',[string]$port,'16','128',$payload,$rejectedOutput,
            'client',$payload,'14529','16',$socketPacing,'dispatch:pool',$descriptor)){$info.ArgumentList.Add($argument)}
        $child=[Diagnostics.Process]::Start($info)
        $errorText=$child.StandardError.ReadToEndAsync()
        if(-not $child.WaitForExit(5000) -or $child.ExitCode -eq 0 -or
            $errorText.GetAwaiter().GetResult() -notmatch $expectedError -or
            (Test-Path -LiteralPath $rejectedOutput)){
            throw 'Invalid pacing/descriptor was not rejected before network mutation.'
        }
        $child.Dispose();$child=$null;$checks++
    }
    foreach($case in @('hot-nagle','hot-wrong-response','hot-large-request')){
        $rejectedOutput=Join-Path $directory 'rejected-hot.json'
        $info.ArgumentList.Clear()
        foreach($argument in @('127.0.0.1','127.0.0.2',[string]$port,'16','128',$(if($case -eq 'hot-large-request'){'1460'}else{'512'}),$rejectedOutput,
            'client',$(if($case -eq 'hot-wrong-response'){'512'}else{'1460'}),'14529','16',$(if($case -eq 'hot-nagle'){'nagle'}else{'nodelay'}),
            'dispatch:pool','servicehot256:pipelined')){$info.ArgumentList.Add($argument)}
        $child=[Diagnostics.Process]::Start($info)
        $errorText=$child.StandardError.ReadToEndAsync()
        if(-not $child.WaitForExit(5000) -or $child.ExitCode -eq 0 -or
            $errorText.GetAwaiter().GetResult() -notmatch $(if($case -eq 'hot-nagle'){'Pipelined service requests require'}else{'Hot service mode requires'}) -or
            (Test-Path -LiteralPath $rejectedOutput)){
            throw 'Invalid hot service pacing was not rejected before network use.'
        }
        $child.Dispose();$child=$null;$checks++
    }
    foreach($case in @('wrong-role','wrong-directory','existing-ready')){
        $rejectedOutput=Join-Path $directory 'rejected-readiness.json'
        $ready=Join-Path $directory 'route-control.ready'
        if($case -eq 'wrong-directory'){$ready=Join-Path (Split-Path $directory) 'route-control.ready'}
        if($case -eq 'existing-ready'){[IO.File]::WriteAllText($ready,'stale')}
        $role=if($case -eq 'wrong-role'){'client'}else{'server'}
        $gcDescriptor=if($case -eq 'wrong-role'){'dispatch:pool'}else{'gc:32:1:graph:16384'}
        $info.ArgumentList.Clear()
        foreach($argument in @('127.0.0.1','127.0.0.2',[string]$port,'16','128','512',$rejectedOutput,
            $role,'512','14529','16','nodelay',$gcDescriptor,'servicewait64:pipelined',$ready)){
            $info.ArgumentList.Add($argument)
        }
        $child=[Diagnostics.Process]::Start($info)
        $errorText=$child.StandardError.ReadToEndAsync()
        if(-not $child.WaitForExit(5000) -or $child.ExitCode -eq 0 -or
            $errorText.GetAwaiter().GetResult() -notmatch 'Fixture readiness gates require|fresh owned fixture readiness file' -or
            (Test-Path -LiteralPath $rejectedOutput)){
            throw 'Invalid or reused fixture readiness was not rejected before heap/network setup.'
        }
        $child.Dispose();$child=$null;$checks++
        if($case -eq 'existing-ready'){Remove-Item -LiteralPath $ready}
    }
    foreach($case in @('outside-prefix','duplicate','server-role')){
        $rejectedOutput=Join-Path $directory 'rejected-cluster.json'
        $clusterSources=@(1..9|ForEach-Object{"198.19.64.$_"})
        if($case -eq 'outside-prefix'){$clusterSources[8]='198.19.68.1'}
        if($case -eq 'duplicate'){$clusterSources[8]='198.19.64.1'}
        $info.ArgumentList.Clear()
        foreach($argument in @(($clusterSources -join ','),'127.0.0.2',[string]$port,'16','128','512',$rejectedOutput,
            $(if($case -eq 'server-role'){'server'}else{'client'}),'16384','14529','16','nodelay')){$info.ArgumentList.Add($argument)}
        $child=[Diagnostics.Process]::Start($info)
        $errorText=$child.StandardError.ReadToEndAsync()
        if(-not $child.WaitForExit(5000) -or $child.ExitCode -eq 0 -or
            $errorText.GetAwaiter().GetResult() -notmatch 'Cluster sources' -or (Test-Path -LiteralPath $rejectedOutput)){
            throw 'Cluster sources outside their bounded owned scope were not rejected before network use.'
        }
        $child.Dispose();$child=$null;$checks++
    }
    foreach($case in @('interval-zero','duration-too-long','bad-interface')){
        $dialReport=Join-Path $directory "dial-$case.json"
        $info.ArgumentList.Clear()
        $dialArgs=switch($case){
            'interval-zero'{@('--route-epoch-dial','5','0','1000','0')}
            'duration-too-long'{@('--route-epoch-dial','5','0','60000','20')}
            'bad-interface'{@('--route-epoch-dial','0','0','1000','20')}
        }
        foreach($argument in $dialArgs+@((Join-Path $directory 'dial.ready'),(Join-Path $directory 'dial.stop'),$dialReport)){$info.ArgumentList.Add($argument)}
        $child=[Diagnostics.Process]::Start($info)
        $errorText=$child.StandardError.ReadToEndAsync()
        if(-not $child.WaitForExit(5000) -or $child.ExitCode -eq 0 -or
            $errorText.GetAwaiter().GetResult() -notmatch 'route-epoch dial requires' -or
            (Test-Path -LiteralPath $dialReport) -or (Test-Path -LiteralPath (Join-Path $directory 'dial.ready'))){
            throw 'An unbounded route-epoch dial was not rejected before any route operation.'
        }
        $child.Dispose();$child=$null;$checks++
    }
    if(-not [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($exe)).GetType('ArrivalTcp').GetMethod('VerifyForwardRowLayout').Invoke($null,@())){
        throw 'The documented forward-row layout did not verify.'
    }
    $checks++
    $serverOutput=Join-Path $directory 'server.json'
    $clientOutput=Join-Path $directory 'client.json'
    $info.ArgumentList.Clear()
    foreach($argument in @('127.0.0.1','127.0.0.2',[string]$port,'16','128','1024',$serverOutput,'server','65536','14529','128','nodelay')) {
        $info.ArgumentList.Add($argument)
    }
    $server=[Diagnostics.Process]::Start($info)
    $serverError=$server.StandardError.ReadToEndAsync()
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while(-not(Test-Path -LiteralPath ($serverOutput+'.ready'))) {
        if($server.HasExited -or $watch.Elapsed.TotalSeconds -gt 5){throw 'Separate server did not become ready.'}
        Start-Sleep -Milliseconds 20
    }
    $probeMethod=[Reflection.Assembly]::Load([IO.File]::ReadAllBytes($exe)).GetType('ArrivalTcp').GetMethod('IsListenerReady')
    if(-not $probeMethod.Invoke($null,@([int]$server.Id,[int]$port)) -or
        $probeMethod.Invoke($null,@([int]$PID,[int]$port))){throw 'Listener readiness did not verify socket ownership.'}
    $info.ArgumentList.Clear()
    foreach($argument in @('127.0.0.1','127.0.0.2',[string]$port,'16','128','1024',$clientOutput,'client','65536','12345','128','nodelay')) {
        $info.ArgumentList.Add($argument)
    }
    $child=[Diagnostics.Process]::Start($info)
    $clientError=$child.StandardError.ReadToEndAsync()
    if(-not $child.WaitForExit(10000) -or $child.ExitCode -ne 0 -or
        -not $server.WaitForExit(5000) -or $server.ExitCode -ne 0){throw 'Separate client/server request exchange failed.'}
    $clientResult=Get-Content $clientOutput -Raw|ConvertFrom-Json
    $serverResult=Get-Content $serverOutput -Raw|ConvertFrom-Json
    if($clientResult.role -ne 'client' -or $serverResult.role -ne 'server' -or
        $clientResult.connections -ne 16 -or $serverResult.connections -ne 16 -or
        $clientResult.bytesSent -ne $serverResult.bytesReceived -or $clientResult.bytesReceived -ne $serverResult.bytesSent -or
        $serverResult.bytesSent -ne 1048576 -or $clientResult.bytesSent -ne 16384 -or
        $clientResult.seed -ne 12345 -or $clientResult.peakInFlight -gt $clientResult.maximumInFlight -or
        $clientResult.meanRequestMilliseconds -le 0 -or -not $clientResult.noDelay -or
        $clientResult.maximumInFlight -ne 128){throw 'Independent endpoint byte/count/seed/latency verification failed.'}
    $checks++
    if($probeMethod.Invoke($null,@([int]$server.Id,[int]$port))){throw 'An exited listener was reported ready.'}
    $checks++
    $flags=[Reflection.BindingFlags]'Static,NonPublic'
    $type=$probeMethod.DeclaringType
    $referenceType=$type.GetNestedType('ReferencedTcpPathFixture')
    $loopback=@(Get-NetIPAddress -IPAddress 127.0.0.1 -AddressFamily IPv4 -ErrorAction Stop)
    if($loopback.Count -ne 1){throw 'The native reference-fixture test requires one loopback interface.'}
    foreach($count in @(1,128)){
        $fixture=$null
        try{
            $fixture=if($count -eq 1){[ArrivalTcp+ReferencedTcpPathFixture]::Create($count)}
                else{$referenceType.GetMethod('Create').Invoke($null,@([int]$count))}
            $fixture.VerifyHeld()
            $fixture.PreparePaths($loopback[0].InterfaceIndex)
            $snapshot=$type.GetMethod('ReadPathPopulation').Invoke($null,@([int]$loopback[0].InterfaceIndex,
                [string[]]@('127.0.0.1'),[int]$loopback[0].InterfaceIndex,[int]$count))
            $connections=$type.GetMethod('CountEstablishedLoopbackFixtureServers').Invoke($null,@([int]$PID,[int]$fixture.Port))
            if($fixture.Count -ne $count -or $fixture.PreparationQueries -ne $count -or $fixture.ReservedSourcePorts -ne [Math]::Min(4096,$count) -or
                $snapshot.ReferencedTcpPaths -ne $count -or $connections -ne $count -or
                $fixture.AvailablePhysicalBytesAtCreate -lt ([long]$count*65536+256MB)){
                throw 'Referenced fixture pairs, actual path range, TCP ownership, or memory admission did not verify.'
            }
            $fixture.Dispose()
            if($type.GetMethod('CountEstablishedConnectionsInLargeTable').Invoke($null,@([int]$PID,[int]$fixture.Port)) -ne 0){
                throw 'Referenced fixture teardown retained owned TCP connections.'
            }
            $checks++
        }finally{if($null -ne $fixture){$fixture.Dispose()}}
    }
    $failure=$null
    try{$null=$referenceType.GetMethod('Create').Invoke($null,@([int]2))}catch{$failure=$_.Exception.GetBaseException()}
    if($failure -isnot [ArgumentException]){throw 'An unbounded referenced fixture size was accepted.'}
    $checks++
    $populationMethod=$type.GetMethod('CreateIdlePathSocketPopulation')
    foreach($case in @(
        @{Sources=[string[]]@();Count=1},
        @{Sources=[string[]]@('198.19.0.1','198.19.0.1');Count=2048},
        @{Sources=[string[]]@('198.19.0.1','198.19.0.13');Count=2048},
        @{Sources=[string[]]@('198.19.0.1','::1');Count=2048},
        @{Sources=[string[]]@('198.19.0.1');Count=100}
    )){
        $failure=$null
        try{$null=$populationMethod.Invoke($null,@($case.Sources,[int]$case.Count,[int[]]@()))}catch{$failure=$_.Exception.GetBaseException()}
        if($failure -isnot [ArgumentException]){throw 'Parallel fixture validation did not reject every source/budget before socket creation.'}
        $checks++
    }
    $memoryType=$type.GetNestedType('MemoryStatus',[Reflection.BindingFlags]::NonPublic)
    $memory=[Activator]::CreateInstance($memoryType)
    if([Runtime.InteropServices.Marshal]::SizeOf($memory) -ne 64){throw 'The memory-admission structure does not match the documented Windows layout.'}
    $memoryType.GetField('Length').SetValue($memory,[uint32]64)
    $memoryArguments=@($memory)
    if(-not $type.GetMethod('GlobalMemoryStatusEx',$flags).Invoke($null,$memoryArguments) -or
        $memoryType.GetField('AvailablePhysical').GetValue($memoryArguments[0]) -le 0){
        throw 'The actual read-only large-heap memory admission query failed.'
    }
    $checks++
    foreach($heapMiB in @(32,1024,2048)){
        $nodes=[long]$type.GetMethod('GraphNodeCount',$flags).Invoke($null,@([int]$heapMiB))
        $expected=([long][Math]::Floor(([long]$heapMiB*1024*1024)/40))-band -2L
        if($nodes -ne $expected -or $nodes -le 0){throw 'Graph node count overflowed or lost the bounded even-root layout.'}
        $checks++
    }
    $savedFields=@{}
    $listener=$null;$receiver=$null
    try{
        foreach($setting in @{exchangesPerConnection=3;serviceRequestPipelining=$true;noDelay=$true}.GetEnumerator()){
            $field=$type.GetField($setting.Key,$flags)
            $savedFields[$setting.Key]=$field.GetValue($null)
            $field.SetValue($null,$setting.Value)
        }
        $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
        $listener.Start()
        $data=[byte[]]::new(512)
        for($i=0;$i -lt $data.Length;$i++){$data[$i]=[byte]($i%251)}
        $send=$type.GetMethod('Send',$flags).Invoke($null,@('127.0.0.1',[Net.IPAddress]::Loopback,
            [int]$listener.LocalEndpoint.Port,$data,$data))
        $receiver=$listener.AcceptTcpClient()
        $receiver.ReceiveTimeout=5000
        $stream=$receiver.GetStream()
        $requests=[byte[]]::new(1536);$offset=0
        while($offset -lt $requests.Length){
            $read=$stream.Read($requests,$offset,$requests.Length-$offset)
            if($read -eq 0){throw 'Pipelined client ended before all independently paced requests.'}
            $offset+=$read
        }
        for($i=0;$i -lt $requests.Length;$i++){
            if($requests[$i] -ne $data[$i%512]){throw 'Pipelined request bytes changed.'}
        }
        for($i=0;$i -lt 3;$i++){$stream.Write($data,0,$data.Length)}
        $receiver.Client.Shutdown([Net.Sockets.SocketShutdown]::Send)
        if(-not $send.Wait(5000) -or $type.GetField('clientPacingWaitsCompleted',$flags).GetValue($null) -ne 2){
            throw 'The client required a response release or did not complete its exact pacing waits.'
        }
        $checks++
    }finally{
        if($null -ne $receiver){$receiver.Dispose()}
        if($null -ne $listener){$listener.Stop()}
        foreach($setting in $savedFields.GetEnumerator()){$type.GetField($setting.Key,$flags).SetValue($null,$setting.Value)}
    }
    $bufferMethod=$probeMethod.DeclaringType.GetMethod('CreateValidationBuffer',$flags)
    foreach($length in @(1,1460,65535,65536,65537,1048576)){
        $buffer=$bufferMethod.Invoke($null,@([int]$length))
        if($buffer.Length -ne [Math]::Min($length,65536)){throw 'Read buffer exceeded the bounded streaming capacity.'}
        $checks++
    }
    $readMethod=$probeMethod.DeclaringType.GetMethod('ReadPattern',$flags)
    foreach($case in @('request-valid','request-corrupt','request-eof','reply-valid','reply-corrupt','reply-eof')){
        $listener=$null;$sender=$null;$receiver=$null
        try{
            $data=[byte[]]::new(65537)
            $patternOffset=if($case.StartsWith('reply')){53}else{0}
            for($i=0;$i -lt $data.Length;$i++){$data[$i]=[byte](($i+$patternOffset)%251)}
            $expected=if($case.StartsWith('reply')){,$data.Clone()}else{$null}
            if($case.EndsWith('corrupt')){$data[65536]=$data[65536] -bxor 1}
            $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
            $listener.Start()
            $sender=[Net.Sockets.TcpClient]::new()
            $sender.Connect([Net.IPAddress]::Loopback,$listener.LocalEndpoint.Port)
            $receiver=$listener.AcceptTcpClient()
            $read=$readMethod.Invoke($null,@($receiver.GetStream(),[byte[]]::new(65536),[int]$data.Length,$expected))
            $sent=if($case.EndsWith('eof')){65536}else{$data.Length}
            $sender.GetStream().Write($data,0,$sent)
            $sender.Client.Shutdown([Net.Sockets.SocketShutdown]::Send)
            $failure=$null
            try{
                if(-not $read.Wait(5000)){throw 'Streaming validation exceeded its deadline.'}
            }catch{$failure=$_.Exception.GetBaseException()}
            if($case.EndsWith('valid')){
                if($null -ne $failure){throw $failure}
            }elseif($failure -isnot [IO.IOException] -or
                ($case.EndsWith('corrupt') -and $failure.Message -notmatch '^(Data|Reply) mismatch\.$') -or
                ($case.EndsWith('eof') -and $failure.Message -ne 'Unexpected EOF.')){
                throw "Streaming validation did not reject the exact malformed payload: $case."
            }
            $checks++
        }finally{
            if($null -ne $sender){$sender.Dispose()}
            if($null -ne $receiver){$receiver.Dispose()}
            if($null -ne $listener){$listener.Stop()}
        }
    }
} finally {
    if($null -ne $child) {
        if(-not $child.HasExited){Stop-Process -Id $child.Id -Force -ErrorAction Stop}
        if(-not $child.WaitForExit(5000)){throw 'Owned arrival process did not terminate.'}
        $child.Dispose()
    }
    if($null -ne $server) {
        if(-not $server.HasExited){Stop-Process -Id $server.Id -Force -ErrorAction Stop}
        if(-not $server.WaitForExit(5000)){throw 'Owned arrival server did not terminate.'}
        $server.Dispose()
    }
    foreach($path in @($output,$exe,(Join-Path $directory 'server.json'),(Join-Path $directory 'server.json.ready'),
        (Join-Path $directory 'client.json'))){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -ErrorAction Stop}}
    Remove-Item -LiteralPath $directory -ErrorAction Stop
}
Write-Output "Passed $checks independent-arrival cases; loopback checks are not performance evidence."
