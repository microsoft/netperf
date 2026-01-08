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

function Convert-ArgStringToArray([string]$s) {
  if ([string]::IsNullOrEmpty($s)) { return @() }
  $pattern = '("((?:\\.|[^"\\])*)"|[^"\s]+)'
  $regexMatches = [regex]::Matches($s, $pattern)
  $out = @()
  foreach ($m in $regexMatches) {
    if ($m.Groups[2].Success) {
      $val = $m.Groups[2].Value
      $val = $val -replace '\\\\', '\\'
      $val = $val -replace '\\"', '"'
    }
    else {
      $val = $m.Groups[1].Value
    }
    $out += $val.Trim()
  }
  return $out
}

function Get-OptionValueOrNull([string[]]$args, [string[]]$names) {
  if (-not $args) { return $null }
  for ($i = 0; $i -lt $args.Count; $i++) {
    if ($names -contains $args[$i]) {
      if (($i + 1) -lt $args.Count) {
        return $args[$i + 1]
      }
      return $null
    }
  }
  return $null
}

function Has-AnyOption([string[]]$args, [string[]]$names) {
  if (-not $args) { return $false }
  foreach ($a in $args) {
    if ($names -contains $a) { return $true }
  }
  return $false
}

# Resolve local echo binaries in current working directory
$cwd = Get-Location
$serverPath = Join-Path $cwd 'echo_server'
$clientPath = Join-Path $cwd 'echo_client'

Ensure-Executable $serverPath
Ensure-Executable $clientPath

# Pick a non-privileged default port (override if caller provided one)
$defaultPort = 5001

$receiverArgs = Convert-ArgStringToArray $ReceiverOptions
$senderArgs = Convert-ArgStringToArray $SenderOptions

$receiverPort = Get-OptionValueOrNull -args $receiverArgs -names @('--port','-p')
$senderPort = Get-OptionValueOrNull -args $senderArgs -names @('--port','-p')

$port = $defaultPort
foreach ($p in @($receiverPort, $senderPort)) {
  if ($p -and ($p -as [int])) {
    $port = [int]$p
    break
  }
}

if (-not (Has-AnyOption -args $receiverArgs -names @('--port','-p'))) {
  $receiverArgs += @('--port', $port)
}

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
$serverPid = Invoke-Command -Session $session -ScriptBlock {
  param([string]$Path, [string[]]$Args, [string]$LogPath)
  
  # Start the server in the background using Start-Process
  $stderrPath = "$LogPath.err"
  $process = Start-Process -FilePath $Path -ArgumentList $Args -RedirectStandardOutput $LogPath -RedirectStandardError $stderrPath -PassThru
  return $process.Id
} -ArgumentList $RemoteServerPath, $receiverArgs, $RemoteServerLogPath
Write-Host "Server PID on peer: $serverPid"
Start-Sleep -Seconds 2

# Run client locally and capture output
Write-Host "Running echo client locally"

$clientArgs = @()
$clientArgs += $senderArgs

if (-not (Has-AnyOption -args $clientArgs -names @('--server','-s'))) {
  $clientArgs += @('--server', $PeerName)
}
if (-not (Has-AnyOption -args $clientArgs -names @('--port','-p'))) {
  $clientArgs += @('--port', $port)
}
if (-not (Has-AnyOption -args $clientArgs -names @('--duration','-d'))) {
  $clientArgs += @('--duration', $Duration)
}

# Execute client binary directly without intermediate shell
$clientOutput = & $clientPath @clientArgs 2>&1
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

Write-Host "Fetching server stderr log from peer"
try {
  Copy-Item -FromSession $session -Path "$RemoteServerLogPath.err" -Destination 'server.err.log'
} catch {
  Write-Host "Failed to copy server.err.log: $_"
}

# Close session
if ($session) { Remove-PSSession $session }

# Return non-zero if client failed
if ($clientExit -ne 0) {
  Write-Host "Client reported non-zero exit: $clientExit"
  exit $clientExit
}
