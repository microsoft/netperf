param(
  [string]$PeerName = "netperf-peer",
  [string]$SenderOptions,
  [string]$ReceiverOptions,
  [string]$Duration = "60",
  [string]$RemoteServerPath = "/tmp/echo_server",
  [string]$RemoteServerLogPath = "/tmp/server.log"
)

$ErrorActionPreference = 'Stop'

function Ensure-Executable($path) {
  if (-not (Test-Path $path)) { throw "Missing binary: $path" }
  try { chmod +x $path } catch { Write-Host "chmod failed (may already be executable): $path" }
}

# Resolve local echo binaries in current working directory
$cwd = Get-Location
$serverPath = Join-Path $cwd 'echo_server'
$clientPath = Join-Path $cwd 'echo_client'

Ensure-Executable $serverPath
Ensure-Executable $clientPath

# Establish SSH PowerShell remoting to Linux peer
Write-Host "Creating PowerShell SSH session to peer: $PeerName"
$session = $null
try {
  $session = New-PSSession -HostName $PeerName
} catch {
  throw "Failed to create SSH PSSession to $PeerName. Ensure SSH keys/config are set. Error: $_"
}

# Copy server binary to peer and ensure executable
Write-Host "Copying server binary to peer at $RemoteServerPath"
Copy-Item -Path $serverPath -Destination $RemoteServerPath -ToSession $session
Invoke-Command -Session $session -ScriptBlock { chmod +x $using:RemoteServerPath }

# Start server in background on peer, capture PID
Write-Host "Starting server on peer"
# Properly escape ReceiverOptions for safe shell execution
$escapedReceiverOptions = $ReceiverOptions -replace "'", "'\"'\"'" # escape single quotes
$startServer = @"
  bash -lc "nohup '$using:RemoteServerPath' $using:escapedReceiverOptions > '$using:RemoteServerLogPath' 2>&1 & echo \`$!"
"@
$serverPid = Invoke-Command -Session $session -ScriptBlock ([ScriptBlock]::Create($startServer))
Write-Host "Server PID on peer: $serverPid"
Start-Sleep -Seconds 2

# Run client locally and capture output
Write-Host "Running echo client locally"
# Properly escape arguments for safe shell execution
$escapedSenderOptions = $SenderOptions -replace "'", "'\"'\"'" # escape single quotes
$escapedDuration = $Duration -replace "[^0-9]", "" # only allow digits
$clientCmd = @"
bash -lc ''$clientPath' $escapedSenderOptions --duration $escapedDuration'
"@
$clientOutput = & pwsh -NoProfile -Command $clientCmd 2>&1
$clientExit = $LASTEXITCODE

# Save client output
"$clientOutput" | Out-File -FilePath "echo_client_output.txt" -Encoding utf8
Write-Host "Client exit: $clientExit"

# Attempt to parse simple metrics from client output
$sent = 0
$received = 0
try {
  $sentMatch = ($clientOutput | Select-String -Pattern "Packets sent: (\d+)")
  $recvMatch = ($clientOutput | Select-String -Pattern "Packets received: (\d+)")
  if ($sentMatch) { $sent = [int]($sentMatch.Matches[0].Groups[1].Value) }
  if ($recvMatch) { $received = [int]($recvMatch.Matches[0].Groups[1].Value) }
} catch { }

# Write a minimal CSV summary
$csvLines = @()
$csvLines += "Test,Sent,Received,Duration"
$csvLines += "LinuxEcho,$sent,$received,$Duration"
$csvLines | Out-File -FilePath "echo_summary.csv" -Encoding utf8

# Stop server on peer and collect logs
Write-Host "Stopping server on peer"
try {
  Invoke-Command -Session $session -ScriptBlock { kill -TERM $using:serverPid } | Out-Null
} catch {
  Write-Host "Kill failed: $_"
}
Start-Sleep -Seconds 1

Write-Host "Fetching server log from peer"
try {
  Copy-Item -FromSession $session -Path $RemoteServerLogPath -Destination 'server.log'
} catch {
  Write-Host "Failed to copy server.log: $_"
}

# Close session
if ($session) { Remove-PSSession $session }

# Return non-zero if client failed
if ($clientExit -ne 0) {
  Write-Host "Client reported non-zero exit: $clientExit"
  exit $clientExit
}
