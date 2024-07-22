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
} else {
    throw "Invalid command: $Command"
}

# TODO: Add commands for windows.
