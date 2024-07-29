param (
    [string]$Command
)

Write-Host "Executing command: $Command"

if ($PSVersionTable.PSVersion.Major -lt 7) {
    $isWindows = $true
}

function SetLinuxLibPath {
    $fullPath = "./artifacts/bin/linux/x64_Release_openssl"
    $SecNetPerfPath = "$fullPath/secnetperf"
    $env:LD_LIBRARY_PATH = "${env:LD_LIBRARY_PATH}:$fullPath"
    chmod +x "$SecNetPerfPath"
}

# Waits for a given driver to be started up to a given timeout.
function Wait-DriverStarted {
    param ($DriverName, $TimeoutMs)
    $stopWatch = [system.diagnostics.stopwatch]::StartNew()
    while ($stopWatch.ElapsedMilliseconds -lt $TimeoutMs) {
        $Driver = Get-Service -Name $DriverName -ErrorAction Ignore
        if ($null -ne $Driver -and $Driver.Status -eq "Running") {
            Write-Host "$DriverName is running"
            return
        }
        Start-Sleep -Seconds 0.1 | Out-Null
    }
    throw "$DriverName failed to start!"
}


$mode = "maxput"
$io = "iocp"
$stats = "0"

if ($Command.Contains("lowlat")) {
    $mode = "lowlat"
}

if ($Command.Contains("epoll")) {
    $io = "epoll"
}

if ($Command.Contains("xdp")) {
    $io = "xdp"
}

if ($Command.Contains("wsk")) {
    $io = "wsk"
}

if ($Command.Contains("stats")) {
    $stats = "1"
}



if ($Command.Contains("/home/secnetperf/_work/quic/artifacts/bin/linux/x64_Release_openssl/secnetperf")) {
    ./artifacts/bin/linux/x64_Release_openssl/secnetperf -exec:$mode -io:$io -stats:$stats
} elseif ($Command.Contains("C:/_work/quic/artifacts/bin/windows/x64_Release_schannel/secnetperf")) {
    ./artifacts/bin/windows/x64_Release_schannel/secnetperf -exec:$mode -io:$io -stats:$stats
} elseif ($Command.Contains("Install_XDP")) {
    Write-Host "(SERVER) Downloading XDP installer"
    $installerUri = $Command.Split(";")[1]
    if ($isWindows) {
        $msiPath = "C:/xdp.msi"
    } else {
        $msiPath = "/var/tmp/xdp.msi"
    }
    Invoke-WebRequest -Uri $installerUri -OutFile $msiPath -UseBasicParsing
    Write-Host "(SERVER) Installing XDP driver locally"
    $Size = Get-FileHash -Path $msiPath
    msiexec.exe /i $msiPath /quiet | Out-Host
    Wait-DriverStarted "xdp" 10000
} elseif ($Command -eq "Install_WSK") {
    # TODO
} else {
    throw "Invalid command: $Command"
}
