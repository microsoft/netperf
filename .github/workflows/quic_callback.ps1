param (
    [string]$Command
)

Write-Host "Executing command: $Command"

if ($Command -eq "/home/secnetperf/_work/quic/artifacts/bin/linux/x64_Release_openssl/secnetperf -exec:lowlat -io:epoll -stats:1") {
    ./artifacts/bin/linux/x64_Release_openssl/secnetperf -exec:lowlat -io:epoll -stats:1 | Out-Null
} elseif ($Command -eq "/home/secnetperf/_work/quic/artifacts/bin/linux/x64_Release_openssl/secnetperf -exec:maxtput -io:epoll -stats:1") {
    ./artifacts/bin/linux/x64_Release_openssl/secnetperf -exec:maxtput -io:epoll -stats:1 | Out-Null
} else {
    throw "Invalid command: $Command"
}
