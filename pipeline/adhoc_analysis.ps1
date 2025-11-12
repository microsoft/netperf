param(
    [Parameter(Mandatory = $false)]
    [int]$RetryCount = 5,

    [Parameter(Mandatory = $false)]
    [boolean]$AnalyzeLatency = $false
)

function Get-NumberFromString {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputString
    )

    # Use regex to extract digits
    $digits = ($InputString -replace '[^\d]', '')

    if ($digits -eq '') {
        throw "No numbers found in input string."
    }

    return [int]$digits / 10
}

function Get-ArrayStats {
    param(
        [Parameter(Mandatory = $true)]
        [double[]]$Numbers
    )

    if ($Numbers.Count -eq 0) {
        throw "Array is empty."
    }

    # Compute mean
    $mean = ($Numbers | Measure-Object -Average).Average

    # Compute variance and standard deviation
    $variance = ($Numbers | ForEach-Object { [math]::Pow($_ - $mean, 2) } | Measure-Object -Average).Average
    $stddev = [math]::Sqrt($variance)

    $AVG = [math]::Round($mean, 4)
    $STD = [math]::Round($stddev, 4)
    Write-Host "Mean: $AVG, StdDev: $STD"

    # Return as an object
    [PSCustomObject]@{
        Mean = [math]::Round($mean, 4)
        StdDev = [math]::Round($stddev, 4)
    }
}

function Get-MetricValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputString,

        [Parameter(Mandatory = $true)]
        [string]$Metric
    )

    # Normalize line breaks
    $InputString = $InputString -replace "`r", ''

    switch ($Metric) {
        "RPS" {
            # Match: Result: 6652 RPS
            if ($InputString -match 'Result:\s*(\d+)\s*RPS') {
                return [int]$matches[1]
            }
        }

        default {
            # Match e.g. "0th: 128" or "50th: 148"
            $pattern = [regex]::Escape($Metric) + ':\s*(\d+)'
            if ($InputString -match $pattern) {
                return [int]$matches[1]
            }
        }
    }

    throw "Metric '$Metric' not found in input."
}


function AnalyzeThroughput {
    Write-Host "================================="
    Write-Host "Starting Analysis For Throughput:"
    Write-Host "Assume: current working directory contains secnetperf.exe"
    Write-Host "Assume: remote host running secnetperf server on maxtput"
    Write-Host "Assume: local host running secnetperf server on maxtput"
    Write-Host "================================="

    Write-Host ">>> Upload scenario to Netperf-Peer over iocp"
    $Upload = @()
    for ($i = 1; $i -le $RetryCount; $i += 1) {
        $res = Invoke-Expression '.\secnetperf.exe -scenario:upload -target:netperf-peer -exec:maxtput -io:iocp'
        Write-Host $res
        $X = Get-NumberFromString -InputString ($res -join ' ')
        Write-Host "Record result: $X"
        $Upload += $X
    }
    $Uploadstats = Get-ArrayStats -Numbers $Upload

    Write-Host ">>> Download scenario to Netperf-Peer over iocp"
    $Download = @()
    for ($i = 1; $i -le $RetryCount; $i += 1) {
        $res = Invoke-Expression '.\secnetperf.exe -scenario:download -target:netperf-peer -exec:maxtput -io:iocp'
        Write-Host $res
        $X = Get-NumberFromString -InputString ($res -join ' ')
        Write-Host "Record result: $X"
        $Download += $X
    }
    $Downloadstats = Get-ArrayStats -Numbers $Download

    Write-Host ">>> Upload scenario to Loopback over iocp"
    $Upload = @()
    for ($i = 1; $i -le $RetryCount; $i += 1) {
        $res = Invoke-Expression '.\secnetperf.exe -scenario:upload -target:127.0.0.1 -exec:maxtput -io:iocp'
        Write-Host $res
        $X = Get-NumberFromString -InputString ($res -join ' ')
        Write-Host "Record result: $X"
        $Upload += $X
    }
    $Uploadstats = Get-ArrayStats -Numbers $Upload

    Write-Host ">>> Download scenario to Loopback over iocp"
    $Download = @()
    for ($i = 1; $i -le $RetryCount; $i += 1) {
        $res = Invoke-Expression '.\secnetperf.exe -scenario:download -target:127.0.0.1 -exec:maxtput -io:iocp'
        Write-Host $res
        $X = Get-NumberFromString -InputString ($res -join ' ')
        Write-Host "Record result: $X"
        $Download += $X
    }
    $Downloadstats = Get-ArrayStats -Numbers $Download
}

function AnalyzeLatency {
    Write-Host "================================="
    Write-Host "Starting Analysis For Latency:"
    Write-Host "Assume: current working directory contains secnetperf.exe"
    Write-Host "Assume: remote host running secnetperf server on lowlat"
    Write-Host "Assume: local host running secnetperf server on lowlat"
    Write-Host "================================="

    Write-Host ">>> Latency scenario to Netperf-Peer over iocp"
    $RPSS = @()
    $ZEROTHS = @()
    $FIFTYTHS = @()
    $NINETYNINTHS = @()
    $MAXES = @()
    for ($i = 1; $i -le $RetryCount; $i += 1) {
        $res = Invoke-Expression '.\secnetperf.exe -scenario:latency -target:netperf-peer -exec:lowlat -io:iocp'
        Write-Host $res
        $RPS = Get-MetricValue -InputString ($res -join ' ') -Metric "RPS"
        Write-Host "Record RPS: $RPS"
        $zeroth = Get-MetricValue -InputString ($res -join ' ') -Metric "0th"
        $fiftyth = Get-MetricValue -InputString ($res -join ' ') -Metric "50th"
        $ninetyninth = Get-MetricValue -InputString ($res -join ' ') -Metric "99th"
        $max = Get-MetricValue -InputString ($res -join ' ') -Metric "99.9999th"
        Write-Host "Record RTTs: 0th = $zeroth, 50th = $fiftyth, 99th = $ninetyninth, 99.9999th = $max"
        $RPSS += $RPS
        $ZEROTHS += $zeroth
        $FIFTYTHS += $fiftyth
        $NINETYNINTHS += $ninetyninth
        $MAXES += $max
    }

    Write-Host "RPS stats: "
    $stats = Get-ArrayStats -Numbers $RPSS

    Write-Host "0th pct RTT stats: "
    $stats = Get-ArrayStats -Numbers $ZEROTHS

    Write-Host "50th pct RTT stats: "
    $stats = Get-ArrayStats -Numbers $FIFTYTHS

    Write-Host "99th pct RTT stats: "
    $stats = Get-ArrayStats -Numbers $NINETYNINTHS

    Write-Host "99.9999th pct RTT stats: "
    $stats = Get-ArrayStats -Numbers $MAXES

    Write-Host ">>> Latency scenario to Loopback over iocp"
    $RPSS = @()
    $ZEROTHS = @()
    $FIFTYTHS = @()
    $NINETYNINTHS = @()
    $MAXES = @()
    for ($i = 1; $i -le $RetryCount; $i += 1) {
        $res = Invoke-Expression '.\secnetperf.exe -scenario:latency -target:127.0.0.1 -exec:lowlat -io:iocp'
        Write-Host $res
        $RPS = Get-MetricValue -InputString ($res -join ' ') -Metric "RPS"
        Write-Host "Record RPS: $RPS"
        $zeroth = Get-MetricValue -InputString ($res -join ' ') -Metric "0th"
        $fiftyth = Get-MetricValue -InputString ($res -join ' ') -Metric "50th"
        $ninetyninth = Get-MetricValue -InputString ($res -join ' ') -Metric "99th"
        $max = Get-MetricValue -InputString ($res -join ' ') -Metric "99.9999th"
        Write-Host "Record RTTs: 0th = $zeroth, 50th = $fiftyth, 99th = $ninetyninth, 99.9999th = $max"
        $RPSS += $RPS
        $ZEROTHS += $zeroth
        $FIFTYTHS += $fiftyth
        $NINETYNINTHS += $ninetyninth
        $MAXES += $max
    }
    Write-Host "RPS stats: "
    $stats = Get-ArrayStats -Numbers $RPSS

    Write-Host "0th pct RTT stats: "
    $stats = Get-ArrayStats -Numbers $ZEROTHS

    Write-Host "50th pct RTT stats: "
    $stats = Get-ArrayStats -Numbers $FIFTYTHS

    Write-Host "99th pct RTT stats: "
    $stats = Get-ArrayStats -Numbers $NINETYNINTHS

    Write-Host "99.9999th pct RTT stats: "
    $stats = Get-ArrayStats -Numbers $MAXES
}

if ($AnalyzeLatency) {
    AnalyzeLatency
} else {
    AnalyzeThroughput
}
