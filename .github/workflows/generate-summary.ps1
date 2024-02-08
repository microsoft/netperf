<#
.SYNOPSIS
    Takes the output json files from the test and generates a markdown summary table.
#>

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
    param ([string]$FileName, [string]$Transport, [array]$Results)

    $row = "`n|"
    $parts = Convert-FileName $FileName
    foreach ($part in $parts) { $row += " $part |" }
    $row += " $Transport |"

    for ($i = 0; $i -lt 3; $i++) {
        if ($i -ge $Results.Count) { $row += " - |" }
        else { $row += " $(($Results[$i] / 1000000).ToString('F2')) |" }
    }

    $Script:markdown += $row
}

# Adds a row to the HPS table.
function Write-HpsRow {
    param ([string]$FileName, [string]$Transport, [array]$Results)

    $row = "`n|"
    $parts = Convert-FileName $FileName
    foreach ($part in $parts) { $row += " $part |" }
    $row += " $Transport |"

    for ($i = 0; $i -lt 3; $i++) {
        if ($i -ge $Results.Count) { $row += " - |" }
        else { $row += " $($Results[$i]) |" }
    }

    $Script:markdown += $row
}

# Adds a row to the RPS/latency table.
function Write-RpsRow {
    param ([string]$FileName, [string]$Transport, [array]$Results)

    $header = "`n|"
    $parts = Convert-FileName $FileName
    foreach ($part in $parts) { $header += " $part |" }
    $header += " $Transport |"

    for ($i = 0; $i -lt $Results.Count; $i+=9) {
        $row = $header
        for ($j = 0; $j -lt 9; $j++) {
            $row += " $($Results[$i+$j]) |"
        }
        $Script:markdown += $row
    }
}

# Write the Upload table.
$markdown = @"
# Upload Throughput (Gbps)
| Env | OS | Version | Arch | TLS | IO | Transport | Result 1 | Result 2 | Result 3 |
| --- | -- | ------- | ---- | --- | -- | --------- | -------- | -------- | -------- |
"@
foreach ($file in $files) {
    $json = Get-Content -Path $file.FullName | ConvertFrom-Json
    try { Write-ThroughputRow $file.Name "quic" $json.'tput-up-quic' } catch { }
    try { Write-ThroughputRow $file.Name "tcp" $json.'tput-up-tcp' } catch { }
}

# Write the Download table.
$markdown += @"
`n
# Download Throughput (Gbps)
| Env | OS | Version | Arch | TLS | IO | Transport | Result 1 | Result 2 | Result 3 |
| --- | -- | ------- | ---- | --- | -- | --------- | -------- | -------- | -------- |
"@
foreach ($file in $files) {
    $json = Get-Content -Path $file.FullName | ConvertFrom-Json
    try { Write-ThroughputRow $file.Name "quic" $json.'tput-down-quic' } catch { }
    try { Write-ThroughputRow $file.Name "tcp" $json.'tput-down-tcp' } catch { }
}

# Write the HPS table.
$markdown += @"
`n
# Handshakes Per Second (HPS)
| Env | OS | Version | Arch | TLS | IO | Transport | Result 1 | Result 2 | Result 3 |
| --- | -- | ------- | ---- | --- | -- | --------- | -------- | -------- | -------- |
"@
foreach ($file in $files) {
    $json = Get-Content -Path $file.FullName | ConvertFrom-Json
    try { Write-HpsRow $file.Name "quic" $json.'hps-conns-100-quic' } catch { }
    try { Write-HpsRow $file.Name "tcp" $json.'hps-conns-100-tcp' } catch { }
}

# Write the RPS table.
$markdown += @"
`n
# Request Per Second (HPS) and Latency (µs)
| Env | OS | Version | Arch | TLS | IO | Transport | Min | P0 | P50 | P90 | P99 | P99.9 | P99.99 | P99.999 | P99.9999 | Max | RPS |
| --- | -- | ------- | ---- | --- | -- | --------- | --- | -- | --- | --- | --- | ----- | ------ | ------- | -------- | --- | --- |
"@
foreach ($file in $files) {
    $json = Get-Content -Path $file.FullName | ConvertFrom-Json
    try { Write-RpsRow $file.Name "quic" $json.'rps-up-512-down-4000-quic' } catch { }
    try { Write-RpsRow $file.Name "tcp" $json.'rps-up-512-down-4000-tcp' } catch { }
}

# Write the markdown to the console and to the summary file.
Write-Host "`n$markdown"
$markdown | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append
