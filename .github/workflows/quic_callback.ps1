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
} elseif ($Command -eq "Install_XDP") {
    Write-Host "Downloading XDP installer"
    $installerUri = (Get-Content "./scripts/xdp.json" | ConvertFrom-Json).installer
    $msiPath = ./artifacts/xdp.msi
    Invoke-WebRequest -Uri $installerUri -OutFile $msiPath -UseBasicParsing
    Write-Host "Installing XDP driver locally"
    msiexec.exe /i $msiPath /quiet | Out-Null
    Wait-DriverStarted "xdp" 10000
} elseif ($Command -eq "Install_WSK") {

} else {
    throw "Invalid command: $Command"
}

# TODO: Add commands for windows.
