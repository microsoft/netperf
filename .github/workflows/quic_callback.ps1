param (
    [string]$Command
)

Write-Host "Executing command: $Command"

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


if ($Command -eq "/home/secnetperf/_work/quic/artifacts/bin/linux/x64_Release_openssl/secnetperf -exec:lowlat -io:epoll -stats:1") {
    SetLinuxLibPath
    ./artifacts/bin/linux/x64_Release_openssl/secnetperf -exec:lowlat -io:epoll -stats:1 | Out-Null
} elseif ($Command -eq "/home/secnetperf/_work/quic/artifacts/bin/linux/x64_Release_openssl/secnetperf -exec:maxtput -io:epoll -stats:1") {
    SetLinuxLibPath
    ./artifacts/bin/linux/x64_Release_openssl/secnetperf -exec:maxtput -io:epoll -stats:1 | Out-Null
} elseif ($Command -eq "/home/secnetperf/_work/quic/artifacts/bin/linux/x64_Release_openssl/secnetperf -exec:maxtput -io:epoll") {
    SetLinuxLibPath
    ./artifacts/bin/linux/x64_Release_openssl/secnetperf -exec:maxtput -io:epoll | Out-Null
} elseif ($Command -eq "/home/secnetperf/_work/quic/artifacts/bin/linux/x64_Release_openssl/secnetperf -exec:lowlat -io:epoll") {
    SetLinuxLibPath
    ./artifacts/bin/linux/x64_Release_openssl/secnetperf -exec:lowlat -io:epoll | Out-Null
} elseif ($Command -eq "C:/_work/quic/artifacts/bin/windows/x64_Release_schannel/secnetperf -exec:maxtput -io:iocp -stats:1") {
    ./artifacts/bin/windows/x64_Release_schannel/secnetperf -exec:maxtput -io:iocp -stats:1
} elseif ($Command -eq "C:/_work/quic/artifacts/bin/windows/x64_Release_schannel/secnetperf -exec:maxtput -io:iocp") {
    ./artifacts/bin/windows/x64_Release_schannel/secnetperf -exec:maxtput -io:iocp
} elseif ($Command -eq "C:/_work/quic/artifacts/bin/windows/x64_Release_schannel/secnetperf -exec:lowlat -io:iocp -stats:1") {
    ./artifacts/bin/windows/x64_Release_schannel/secnetperf -exec:lowlat -io:iocp -stats:1
} elseif ($Command -eq "C:/_work/quic/artifacts/bin/windows/x64_Release_schannel/secnetperf -exec:lowlat -io:iocp") {
    ./artifacts/bin/windows/x64_Release_schannel/secnetperf -exec:lowlat -io:iocp
} elseif ($Command.Contains("Install_XDP")) {
    Write-Host "(SERVER) Downloading XDP installer"
    whoami
    $installerUri = $Command.Split(";")[1]
    $msiPath = "./artifacts/xdp.msi"
    Invoke-WebRequest -Uri $installerUri -OutFile $msiPath -UseBasicParsing
    Write-Host "(SERVER) Installing XDP driver locally"
    $Size = Get-FileHash -Path $msiPath
    Write-Host "(SERVER) MSI file hash: $Size"
    msiexec.exe /i $msiPath /quiet | Out-Host
    Wait-DriverStarted "xdp" 10000
} elseif ($Command -eq "Install_WSK") {

} else {
    throw "Invalid command: $Command"
}

# TODO: Add commands for windows.
