$ErrorActionPreference = 'Stop'

./netperfrepo/set-netperf-context.ps1 `
    -Matrix $env:NETPERF_MATRIX `
    -SyncerSecret $env:NETPERF_SYNCER_SECRET `
    -GithubRunId $env:NETPERF_GITHUB_RUN_ID

Import-Module ./netperfrepo/netperf-lib.psm1

$secNetPerfParameters = @{
    LogProfile = $env:NETPERF_LOG_PROFILE
    MsQuicCommit = $env:NETPERF_MSQUIC_COMMIT
    environment = $env:NETPERF_ENVIRONMENT
    plat = $env:NETPERF_PLATFORM
    os = $env:NETPERF_OS
    arch = $env:NETPERF_ARCH
    tls = $env:NETPERF_TLS
    io = $env:NETPERF_IO
    filter = $env:NETPERF_FILTER
}

./scripts/secnetperf.ps1 @secNetPerfParameters
