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

  # Parse a simple shell-like argument string into an array.
  # Supports whitespace splitting, single/double quotes, and backslash escaping
  # (outside single quotes).
  $tokens = New-Object System.Collections.Generic.List[string]
  $current = New-Object System.Text.StringBuilder
  $inSingle = $false
  $inDouble = $false
  $escapeNext = $false

  $chars = $s.ToCharArray()
  for ($i = 0; $i -lt $chars.Length; $i++) {
    $ch = $chars[$i]
    if ($escapeNext) {
      [void]$current.Append($ch)
      $escapeNext = $false
      continue
    }

    if (-not $inSingle -and $ch -eq '\\') {
      # Outside single quotes, treat backslash as an escape.
      # Inside double quotes, only escape a limited set of characters.
      if (-not $inDouble) {
        $escapeNext = $true
        continue
      }

      $next = if (($i + 1) -lt $chars.Length) { $chars[$i + 1] } else { [char]0 }
      if ($next -eq '"' -or $next -eq '\\' -or $next -eq '$' -or $next -eq '`') {
        $escapeNext = $true
        continue
      }

      # Otherwise, keep the backslash literal inside double quotes.
      [void]$current.Append($ch)
      continue
    }

    if (-not $inDouble -and $ch -eq "'") {
      $inSingle = -not $inSingle
      continue
    }

    if (-not $inSingle -and $ch -eq '"') {
      $inDouble = -not $inDouble
      continue
    }

    if (-not $inSingle -and -not $inDouble -and [char]::IsWhiteSpace($ch)) {
      if ($current.Length -gt 0) {
        $tokens.Add($current.ToString())
        [void]$current.Clear()
      }
      continue
    }

    [void]$current.Append($ch)
  }

  if ($escapeNext) {
    [void]$current.Append('\\')
  }

  # Check for unclosed quotes
  if ($inSingle -or $inDouble) {
    $quoteType = if ($inSingle) { "'" } else { '"' }
    throw "Unclosed quote detected in input: $s (missing closing $quoteType)"
  }

  if ($current.Length -gt 0) {
    $tokens.Add($current.ToString())
  }

  return [string[]]$tokens.ToArray()
}

function Get-OptionValueOrNull(
  [string[]]$args,
  [string[]]$names,
  [string[]]$knownOptionsWithValues = @('--server','-s','--port','-p','--duration','-d')
) {
  if (-not $args) { return $null }
  $knownSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
  foreach ($n in $knownOptionsWithValues) { [void]$knownSet.Add($n) }

  for ($i = 0; $i -lt $args.Count; $i++) {
    if ($names -contains $args[$i]) {
      # Avoid treating a token as an option if it's actually the value of a previous option.
      if ($i -gt 0 -and $knownSet.Contains($args[$i - 1])) {
        continue
      }

      if (($i + 1) -ge $args.Count) { return $null }
      $candidate = $args[$i + 1]
      if ([string]::IsNullOrEmpty($candidate)) { return $null }
      if ($candidate.StartsWith('-')) { return $null }
      return $candidate
    }
  }
  return $null
}

function Has-AnyOption(
  [string[]]$args,
  [string[]]$names,
  [string[]]$knownOptionsWithValues = @('--server','-s','--port','-p','--duration','-d')
) {
  if (-not $args) { return $false }
  $knownSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
  foreach ($n in $knownOptionsWithValues) { [void]$knownSet.Add($n) }

  for ($i = 0; $i -lt $args.Count; $i++) {
    if ($names -contains $args[$i]) {
      # Avoid counting a token as an option if it's the value of a previous known option.
      if ($i -gt 0 -and $knownSet.Contains($args[$i - 1])) {
        continue
      }
      return $true
    }
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

function Parse-PortOrNull([string]$value) {
  if ([string]::IsNullOrWhiteSpace($value)) { return $null }
  $p = 0
  if (-not [int]::TryParse($value, [ref]$p)) { return $null }
  if ($p -lt 1 -or $p -gt 65535) {
    throw "Invalid port '$value'. Expected an integer in range 1-65535."
  }
  return $p
}

$receiverArgs = Convert-ArgStringToArray $ReceiverOptions
$senderArgs = Convert-ArgStringToArray $SenderOptions

$receiverPort = Get-OptionValueOrNull -args $receiverArgs -names @('--port','-p')
$senderPort = Get-OptionValueOrNull -args $senderArgs -names @('--port','-p')

$receiverPortInt = Parse-PortOrNull $receiverPort
$senderPortInt = Parse-PortOrNull $senderPort

if ($null -ne $receiverPortInt -and $null -ne $senderPortInt -and $receiverPortInt -ne $senderPortInt) {
  throw "SenderOptions and ReceiverOptions specify different ports ($receiverPortInt vs $senderPortInt). Use a single port for both client and server, or omit one and let the script apply a consistent port."
}

$port = if ($null -ne $receiverPortInt) { $receiverPortInt } elseif ($null -ne $senderPortInt) { $senderPortInt } else { $defaultPort }

if (-not (Has-AnyOption -args $receiverArgs -names @('--port','-p'))) {
  $receiverArgs += @('--port', "$port")
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

$RemoteServerErrLogPath = [System.IO.Path]::ChangeExtension($RemoteServerLogPath, 'err.log')

# Start server in background on peer, capture PID
Write-Host "Starting server on peer"
$serverPid = Invoke-Command -Session $session -ScriptBlock {
  param([string]$Cmd)

  $pidText = & /bin/bash -lc $Cmd
  $serverPidValue = 0
  if (-not [int]::TryParse(($pidText | Select-Object -First 1), [ref]$serverPidValue)) {
    throw "Failed to start server via nohup; unexpected pid output: $pidText"
  }
  return $serverPidValue
} -ArgumentList @(
  $(
    function Quote-Bash([Parameter(Mandatory = $true)][string]$s) {
      # Single-quote for bash; escape embedded single-quotes safely.
      $replacement = "'" + '"' + "'" + '"' + "'"
      return "'" + $s.Replace("'", $replacement) + "'"
    }

    # Build the full command locally as a single string to avoid any remoting/serialization
    # oddities that can cause array arguments to be dropped.
    $quotedServer = Quote-Bash $RemoteServerPath
    $quotedArgs = ($receiverArgs | ForEach-Object { Quote-Bash $_ }) -join ' '
    $quotedStdout = Quote-Bash $RemoteServerLogPath
    $quotedStderr = Quote-Bash $RemoteServerErrLogPath
    "nohup $quotedServer $quotedArgs > $quotedStdout 2> $quotedStderr < /dev/null & echo `$!"
  )
)
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
  $clientArgs += @('--port', "$port")
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
  Invoke-Command -Session $session -ScriptBlock { & /bin/kill -TERM $using:serverPid } | Out-Null
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
  Copy-Item -FromSession $session -Path $RemoteServerErrLogPath -Destination 'server.err.log'
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
