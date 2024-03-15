<#
.SYNOPSIS
    Takes the output json files from the test and generates a markdown summary table.

.PARAMETER BlockOnFailure
    If true, the workflow will fail if there are any regression results.
#>

param (
    [Parameter(Mandatory = $false)]
    [string]$BlockOnFailure = "false"
)

$blockOnFailure = $BlockOnFailure -eq "true"

Set-StrictMode -Version "Latest"
$PSDefaultParameterValues["*:ErrorAction"] = "Stop"

# Parse in all the json files in the ./artifacts/logs directory.
$files = Get-ChildItem -Path ./artifacts/logs -Filter *.json

# Decodes the file name into the individual parts.
# Example: `json-test-results-lab-windows-windows-2022-x64-schannel-iocp.json`
function Convert-FileName {
    param ([string]$FileName)
    $name = $FileName -replace 'json-test-results-', ''
    $name = $name -replace '.json', ''
    $name = $name -replace 'windows-windows', 'windows'
    $name = $name -replace 'linux-ubuntu', 'ubuntu'
    return $name -split '-'
}

# Adds a row to the throughput table, converting the output from kbps to gbps.
function Write-ThroughputRow {
    param ([string]$FileName, [string]$Transport, [array]$Results, [object]$Regression)

    $row = "`n|"

    if ($Regression.HasRegression) {
        $row += "😡 |"
    } else {
        $row += "✅ |"
    }

    $parts = Convert-FileName $FileName
    foreach ($part in $parts) { $row += " $part |" }
    $row += " $Transport |"

    for ($i = 0; $i -lt 3; $i++) {
        if ($i -ge $Results.Count) { $row += " - |" }
        else { $row += " $(($Results[$i] / 1000000).ToString('F2')) |" }
    }

    $row += " " + $Regression.CumulativeResult + " |"
    $row += " " + $Regression.Baseline + " |"
    $row += " " + $Regression.BestResult + " |"
    if ($Regression.BestResultCommit -eq "N/A") { $row += "N/A |" }
    else { $row += "[Github](https://github.com/microsoft/msquic/commit/" + $Regression.BestResultCommit + ") |" }

    $Script:markdown += $row
}

# Adds a row to the HPS table.
function Write-HpsRow {
    param ([string]$FileName, [string]$Transport, [array]$Results, [object]$Regression)
    $row = "`n|"
    if ($Regression.HasRegression) {
        $row += "😡 |"
    } else {
        $row += "✅ |"
    }

    $parts = Convert-FileName $FileName
    foreach ($part in $parts) { $row += " $part |" }
    $row += " $Transport |"

    for ($i = 0; $i -lt 3; $i++) {
        if ($i -ge $Results.Count) { $row += " - |" }
        else { $row += " $($Results[$i]) |" }
    }

    $row += " " + $Regression.CumulativeResult + " |"
    $row += " " + $Regression.Baseline + " |"
    $row += " " + $Regression.BestResult + " |"
    if ($Regression.BestResultCommit -eq "N/A") { $row += "N/A |" }
    else { $row += "[Github](https://github.com/microsoft/msquic/commit/" + $Regression.BestResultCommit + ") |" }

    $Script:markdown += $row
}

# Adds a row to the RPS/latency table.
# RPS and latency is special, in that we write each attempt as a separate row (instead of Result 1, Result 2, ... etc.)
function Write-RpsRow {
    param ([string]$FileName, [string]$Transport, [array]$Results, [object]$Regression)
    $header = "`n|"
    if ($Regression.HasRegression) {
        $header += "😡 |"
    } else {
        $header += "✅ |"
    }
    $parts = Convert-FileName $FileName
    foreach ($part in $parts) { $header += " $part |" }
    $header += " $Transport |"

    for ($i = 0; $i -lt $Results.Count; $i+=9) {
        $row = $header
        for ($j = 0; $j -lt 9; $j++) {
            $row += " $($Results[$i+$j]) |"
        }

        $row += " " + $Regression.CumulativeResult + " |"
        $row += " " + $Regression.Baseline + " |"
        $row += " " + $Regression.BestResult + " |"
        if ($Regression.BestResultCommit -eq "N/A") { $row += "N/A |" }
        else { $row += "[Github](https://github.com/microsoft/msquic/commit/" + $Regression.BestResultCommit + ") |" }

        $Script:markdown += $row
    }
}

# Truncate the result to 2 decimal places.
function CleanResult {
    param ([string]$Result)
    $Result = [math]::Round([float]$Result, 2)
    $Result = [string]($Result)
    return $Result
}

$hasRegression = $false

# Write the Upload table.
$markdown = @"
# Upload Throughput (Gbps)
| Pass/Fail | Env | OS | Version | Arch | TLS | IO | Transport | Result 1 | Result 2 | Result 3 | CumulativeResult | Baseline | BestResult | BestResultCommit |
| --------- | --- | -- | ------- | ---- | --- | -- | --------- | -------- | -------- | -------- | ---------------- | -------- | ---------- | ---------------- |
"@
foreach ($file in $files) {
    $json = Get-Content -Path $file.FullName | ConvertFrom-Json
    # We store a 'CumulativeResult' in the json because we can't always assume we use the average to aggregate runs. We might use the median for example for a test.
    # NOTE: Do we want to include a column "AggregateFunction" that details how we got the cumulative result? (AVG, MEDIAN... etc.)
    $RegressionQuic = @{
        Baseline = "N/A"
        BestResult = "N/A"
        BestResultCommit = "N/A"
        CumulativeResult = "N/A"
        AggregateFunction = "N/A"
        HasRegression = $false
    }
    $RegressionTcp = @{
        Baseline = "N/A"
        BestResult = "N/A"
        BestResultCommit = "N/A"
        CumulativeResult = "N/A"
        AggregateFunction = "N/A"
        HasRegression = $false
    }
    try {
        $RegressionQuic = $json.'tput-up-quic-regression'
        $RegressionTcp = $json.'tput-up-tcp-regression'
        $RegressionQuic.CumulativeResult = CleanResult ($RegressionQuic.CumulativeResult / 1000000)
        $RegressionQuic.BestResult = CleanResult ($RegressionQuic.BestResult / 1000000)
        $RegressionQuic.Baseline = CleanResult ($RegressionQuic.Baseline / 1000000)
        $RegressionTcp.CumulativeResult = CleanResult ($RegressionTcp.CumulativeResult / 1000000)
        $RegressionTcp.BestResult = CleanResult ($RegressionTcp.BestResult / 1000000)
        $RegressionTcp.Baseline = CleanResult ($RegressionTcp.Baseline / 1000000)
        $hasRegression = $hasRegression -or $RegressionQuic.HasRegression -or $RegressionTcp.HasRegression
    } catch { Write-Host $_ }
    try { Write-ThroughputRow $file.Name "quic" $json.'tput-up-quic' $RegressionQuic } catch { Write-Host $_ }
    try { Write-ThroughputRow $file.Name "tcp" $json.'tput-up-tcp' $RegressionTcp } catch { Write-Host $_ }
}

# Write the Download table.
$markdown += @"
# Download Throughput (Gbps)
| Pass/Fail | Env | OS | Version | Arch | TLS | IO | Transport | Result 1 | Result 2 | Result 3 | CumulativeResult | Baseline | BestResult | BestResultCommit |
| --------- | --- | -- | ------- | ---- | --- | -- | --------- | -------- | -------- | -------- | ---------------- | -------- | ---------- | ---------------- |
"@
foreach ($file in $files) {
    $json = Get-Content -Path $file.FullName | ConvertFrom-Json
    # We store a 'CumulativeResult' in the json because we can't always assume we use the average to aggregate runs. We might use the median for example for a test.
    # TODO: Do we want to include a column "AggregateFunction" that details how we got the cumulative result? (AVG, MEDIAN... etc.)
    $RegressionQuic = @{
        Baseline = "N/A"
        BestResult = "N/A"
        BestResultCommit = "N/A"
        CumulativeResult = "N/A"
        AggregateFunction = "N/A"
        HasRegression = $false
    }
    $RegressionTcp = @{
        Baseline = "N/A"
        BestResult = "N/A"
        BestResultCommit = "N/A"
        CumulativeResult = "N/A"
        AggregateFunction = "N/A"
        HasRegression = $false
    }
    try {
        $RegressionQuic = $json.'tput-down-quic-regression'
        $RegressionTcp = $json.'tput-down-tcp-regression'
        $RegressionQuic.CumulativeResult = CleanResult ($RegressionQuic.CumulativeResult / 1000000)
        $RegressionQuic.BestResult = CleanResult ($RegressionQuic.BestResult / 1000000)
        $RegressionQuic.Baseline = CleanResult ($RegressionQuic.Baseline / 1000000)
        $RegressionTcp.CumulativeResult = CleanResult ($RegressionTcp.CumulativeResult / 1000000)
        $RegressionTcp.BestResult = CleanResult ($RegressionTcp.BestResult / 1000000)
        $RegressionTcp.Baseline = CleanResult ($RegressionTcp.Baseline / 1000000)
        $hasRegression = $hasRegression -or $RegressionQuic.HasRegression -or $RegressionTcp.HasRegression
    } catch { Write-Host $_ }
    try { Write-ThroughputRow $file.Name "quic" $json.'tput-down-quic' $RegressionQuic } catch { Write-Host $_ }
    try { Write-ThroughputRow $file.Name "tcp" $json.'tput-down-tcp' $RegressionTcp } catch { Write-Host $_ }
}

# Write the HPS table.
$markdown += @"
`n
# Handshakes Per Second (HPS)
| Pass/Fail | Env | OS | Version | Arch | TLS | IO | Transport | Result 1 | Result 2 | Result 3 | CumulativeResult | Baseline | BestResult | BestResultCommit |
| --------- | --- | -- | ------- | ---- | --- | -- | --------- | -------- | -------- | -------- | ---------------- | -------- | ---------- | ---------------- |
"@
foreach ($file in $files) {
    $json = Get-Content -Path $file.FullName | ConvertFrom-Json
    $RegressionQuic = @{
        Baseline = "N/A"
        BestResult = "N/A"
        BestResultCommit = "N/A"
        CumulativeResult = "N/A"
        AggregateFunction = "N/A"
        HasRegression = $false
    }
    $RegressionTcp = @{
        Baseline = "N/A"
        BestResult = "N/A"
        BestResultCommit = "N/A"
        CumulativeResult = "N/A"
        AggregateFunction = "N/A"
        HasRegression = $false
    }
    try {
        $RegressionQuic = $json.'hps-conns-100-quic-regression'
        $RegressionTcp = $json.'hps-conns-100-tcp-regression'
        $RegressionQuic.CumulativeResult = CleanResult ($RegressionQuic.CumulativeResult)
        $RegressionQuic.BestResult = CleanResult ($RegressionQuic.BestResult)
        $RegressionQuic.Baseline = CleanResult ($RegressionQuic.Baseline)
        $RegressionTcp.CumulativeResult = CleanResult ($RegressionTcp.CumulativeResult)
        $RegressionTcp.BestResult = CleanResult ($RegressionTcp.BestResult)
        $RegressionTcp.Baseline = CleanResult ($RegressionTcp.Baseline)
        $hasRegression = $hasRegression -or $RegressionQuic.HasRegression -or $RegressionTcp.HasRegression
    } catch { Write-Host $_ }
    try { Write-HpsRow $file.Name "quic" $json.'hps-conns-100-quic' $RegressionQuic } catch { Write-Host $_ }
    try { Write-HpsRow $file.Name "tcp" $json.'hps-conns-100-tcp' $RegressionTcp } catch { Write-Host $_ }
}

# Write the RPS table.
$markdown += @"
`n
# Request Per Second (HPS) and Latency (µs)
| Pass/Fail | Env | OS | Version | Arch | TLS | IO | Transport | Min | P50 | P90 | P99 | P99.9 | P99.99 | P99.999 | P99.9999 | RPS | CumulativeRPS |
| --------- | --- | -- | ------- | ---- | --- | -- | --------- | --- | --- | --- | --- | ----- | ------ | ------- | -------- | --- | ------------- |
"@
foreach ($file in $files) {
    # TODO: Right now, we are not using a watermark based method for regression detection of latency percentile values because we don't know how to determine a "Best Ever" distribution.
    #       (we are just looking at P0, P50, P99 columns, and computing the baseline for each percentile as the mean - 2 * std of the last 20 runs. )
    #       So, the summary table omits a "BestEver" and "Baseline" column for latency. In fact, we ignore the "mean - 2*std" signal entirely. Need to determine how we compare distributions.

    $json = Get-Content -Path $file.FullName | ConvertFrom-Json
    $RegressionQuic = @{
        Baseline = "N/A"
        BestResult = "N/A"
        BestResultCommit = "N/A"
        CumulativeResult = "N/A"
        AggregateFunction = "N/A"
        HasRegression = $false
    }
    $RegressionTcp = @{
        Baseline = "N/A"
        BestResult = "N/A"
        BestResultCommit = "N/A"
        CumulativeResult = "N/A"
        AggregateFunction = "N/A"
        HasRegression = $false
    }
    try {
        $RegressionQuic = $json.'rps-up-512-down-4000-quic-regression'
        $RegressionTcp = $json.'rps-up-512-down-4000-tcp-regression'
        $RegressionQuic.CumulativeResult = CleanResult ($RegressionQuic.CumulativeResult)
        $RegressionQuic.BestResult = CleanResult ($RegressionQuic.BestResult)
        $RegressionQuic.Baseline = CleanResult ($RegressionQuic.Baseline)
        $RegressionTcp.CumulativeResult = CleanResult ($RegressionTcp.CumulativeResult)
        $RegressionTcp.BestResult = CleanResult ($RegressionTcp.BestResult)
        $RegressionTcp.Baseline = CleanResult ($RegressionTcp.Baseline)
        $hasRegression = $hasRegression -or $RegressionQuic.HasRegression -or $RegressionTcp.HasRegression
    } catch { Write-Host $_ }
    try { Write-RpsRow $file.Name "quic" $json.'rps-up-512-down-4000-quic' $RegressionQuic } catch { Write-Host $_ }
    try { Write-RpsRow $file.Name "tcp" $json.'rps-up-512-down-4000-tcp' $RegressionTcp } catch { Write-Host $_ }
}

# Write the markdown to the console and to the summary file.
Write-Host "`n$markdown"
$markdown | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append

if ($hasRegression) {
    Write-Host "This step has regression results. Please check the summary file for details."

    # Don't fail the entire workflow if we want to publish results (when we merge code or manually trigger a new workflow with "publish results" checked).
    if ($blockOnFailure) {
        exit 1
    }
}
