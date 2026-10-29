# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
$ErrorActionPreference='Stop'
$directory=Join-Path ([IO.Path]::GetTempPath()) ('owned-tcp-table-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $directory
$assembly=Join-Path $directory 'OwnedTcpTable.exe'
$listener=$null;$sockets=[Collections.Generic.List[IDisposable]]::new()
try {
    & "$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:exe /platform:x64 `
        "/out:$assembly" (Join-Path $PSScriptRoot 'ArrivalTcp.cs')
    if($LASTEXITCODE){throw 'Owned TCP table helper compilation failed.'}
    $null=[Reflection.Assembly]::Load([IO.File]::ReadAllBytes($assembly))
    foreach($source in @('127.0.0.1','198.19.240.1')){
        $rejected=$false
        try{$null=[ArrivalTcp]::CreateIdlePathSockets($source,1024,[int[]]@())}catch{
            if($_.Exception.InnerException -isnot [ArgumentException]){throw}
            $rejected=$true
        }
        if(-not $rejected){throw 'An unowned UDP path-population source was accepted.'}
    }
    $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
    $listener.Start()
    $port=$listener.LocalEndpoint.Port
    if(-not [ArrivalTcp]::IsListenerReady($PID,$port) -or [ArrivalTcp]::CountEstablishedConnections($PID,$port) -ne 0){
        throw 'Listener readiness must not imply established connections.'
    }
    for($i=0;$i -lt 2;$i++){
        $client=[Net.Sockets.TcpClient]::new();$sockets.Add($client)
        $client.Connect([Net.IPAddress]::Loopback,$port)
        $sockets.Add($listener.AcceptTcpClient())
    }
    if([ArrivalTcp]::CountEstablishedConnections($PID,$port) -ne 2 -or
        [ArrivalTcp]::CountEstablishedConnections(($PID+1000000),$port) -ne 0){
        throw 'The fast table reader did not isolate established server endpoints by PID and port.'
    }
    $loopback=@([Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()|
        Where-Object NetworkInterfaceType -eq Loopback)
    if($loopback.Count -ne 1 -or [ArrivalTcp]::CountIpv4Paths($loopback[0].GetIPProperties().GetIPv4Properties().Index,'127.0.0.1') -lt 1){
        throw 'The native path-table reader did not find the ordinary loopback path.'
    }
    Write-Host 'Passed owned TCP-table and native IP-path enumeration checks with ordinary loopback connections.'
}finally{
    foreach($socket in $sockets){$socket.Dispose()}
    if($null -ne $listener){$listener.Stop()}
    if(Test-Path -LiteralPath $assembly){Remove-Item -LiteralPath $assembly}
    Remove-Item -LiteralPath $directory
}
