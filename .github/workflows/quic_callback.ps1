param (
    [string]$Command
)

Write-Host "Executing command: $Command"

if ($Command -eq "START_SERVER_LOWLAT") {
    ./artifacts/bin/linux/x64_Release_openssl/secnetperf -exec:lowlat -io:epoll -stats:1 | Out-Null
} elseif ($Command -eq "START_SERVER_MAXTPUT") {
    ./artifacts/bin/linux/x64_Release_openssl/secnetperf -exec:maxtput -io:epoll -stats:1 | Out-Null
} else {
    throw "Invalid command: $Command"
}
