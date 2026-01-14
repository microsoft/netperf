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

# Collect system information from the peer
Write-Host "Collecting system and network diagnostics from peer"
try {
  Invoke-Command -Session $session -ScriptBlock {
    & /bin/bash -lc "uname -a > /tmp/system_info.txt 2>&1"
    & /bin/bash -lc "lscpu >> /tmp/system_info.txt 2>&1"
    & /bin/bash -lc "cat /proc/cpuinfo | grep 'model name' | head -1 >> /tmp/system_info.txt 2>&1"
    & /bin/bash -lc "free -h >> /tmp/system_info.txt 2>&1"
    & /bin/bash -lc "cat /proc/sys/net/core/rmem_max >> /tmp/system_info.txt 2>&1"
    & /bin/bash -lc "cat /proc/sys/net/core/wmem_max >> /tmp/system_info.txt 2>&1"
    & /bin/bash -lc "ethtool -g eth0 >> /tmp/system_info.txt 2>&1 || ethtool -g ens1 >> /tmp/system_info.txt 2>&1 || echo 'ethtool not available' >> /tmp/system_info.txt"
    & /bin/bash -lc "echo '=== Network Interfaces ===' >> /tmp/system_info.txt"
    & /bin/bash -lc "ip link show >> /tmp/system_info.txt 2>&1"
    & /bin/bash -lc "echo '=== RSS Configuration ===' >> /tmp/system_info.txt"
    & /bin/bash -lc "ethtool -x eth0 2>/dev/null | head -20 >> /tmp/system_info.txt 2>&1 || ethtool -x ens1 2>/dev/null | head -20 >> /tmp/system_info.txt 2>&1 || echo 'ethtool -x not available' >> /tmp/system_info.txt"
    & /bin/bash -lc "echo '=== RX/TX Ring Parameters ===' >> /tmp/system_info.txt"
    & /bin/bash -lc "ethtool -g eth0 2>/dev/null >> /tmp/system_info.txt 2>&1 || ethtool -g ens1 2>/dev/null >> /tmp/system_info.txt 2>&1"
    & /bin/bash -lc "echo '=== Interrupt Configuration ===' >> /tmp/system_info.txt"
    & /bin/bash -lc "cat /proc/interrupts | head -20 >> /tmp/system_info.txt 2>&1"
  }
} catch {
  Write-Host "Warning: Failed to collect system info: $_"
}

# Copy server binary to peer and ensure executable
Write-Host "Copying server binary to peer at $RemoteServerPath"
Copy-Item -Path $serverPath -Destination $RemoteServerPath -ToSession $session
Invoke-Command -Session $session -ScriptBlock { chmod +x $using:RemoteServerPath }

$RemoteServerErrLogPath = [System.IO.Path]::ChangeExtension($RemoteServerLogPath, 'err.log')

# Start server in background on peer, capture PID
Write-Host "Starting server on peer with CPU profiling"
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

# Start perf profiling on the server process
Write-Host "Starting perf record on server process"
$perfPid = Invoke-Command -Session $session -ScriptBlock {
  param([int]$TargetPid)
  $perfCmd = "nohup perf record -F 99 -g -p $TargetPid -o /tmp/server_perf.data > /tmp/perf.log 2>&1 < /dev/null & echo `$!"
  $perfPidText = & /bin/bash -lc $perfCmd
  $perfPidValue = 0
  if (-not [int]::TryParse(($perfPidText | Select-Object -First 1), [ref]$perfPidValue)) {
    Write-Host "Warning: Failed to start perf; output: $perfPidText"
    return 0
  }
  return $perfPidValue
} -ArgumentList $serverPid
Write-Host "Perf PID on peer: $perfPid"

# Start mpstat monitoring
Write-Host "Starting mpstat monitoring on peer"
$mpstatPid = Invoke-Command -Session $session -ScriptBlock {
  $mpstatCmd = "nohup mpstat 1 > /tmp/mpstat.log 2>&1 < /dev/null & echo `$!"
  $mpstatPidText = & /bin/bash -lc $mpstatCmd
  $mpstatPidValue = 0
  if (-not [int]::TryParse(($mpstatPidText | Select-Object -First 1), [ref]$mpstatPidValue)) {
    Write-Host "Warning: Failed to start mpstat; output: $mpstatPidText"
    return 0
  }
  return $mpstatPidValue
}
Write-Host "Mpstat PID on peer: $mpstatPid"

# Start top monitoring for the server process
Write-Host "Starting top monitoring on peer"
$topPid = Invoke-Command -Session $session -ScriptBlock {
  param([int]$TargetPid)
  $topCmd = "nohup top -b -d 1 -p $TargetPid > /tmp/top.log 2>&1 < /dev/null & echo `$!"
  $topPidText = & /bin/bash -lc $topCmd
  $topPidValue = 0
  if (-not [int]::TryParse(($topPidText | Select-Object -First 1), [ref]$topPidValue)) {
    Write-Host "Warning: Failed to start top; output: $topPidText"
    return 0
  }
  return $topPidValue
} -ArgumentList $serverPid
Write-Host "Top PID on peer: $topPid"

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
$duration = 0
$sendRate = 0
$recvRate = 0
try {
  $sentMatch = ($clientOutput | Select-String -Pattern "Packets sent: (\d+) \((\d+) pps\)")
  $recvMatch = ($clientOutput | Select-String -Pattern "Packets received: (\d+) \((\d+) pps\)")
  $durationMatch = ($clientOutput | Select-String -Pattern "Duration: ([\d.]+) seconds")
  
  if ($sentMatch) { 
    $sent = [int]($sentMatch.Matches[0].Groups[1].Value)
    $sendRate = [int]($sentMatch.Matches[0].Groups[2].Value)
  }
  if ($recvMatch) { 
    $received = [int]($recvMatch.Matches[0].Groups[1].Value)
    $recvRate = [int]($recvMatch.Matches[0].Groups[2].Value)
  }
  if ($durationMatch) {
    $duration = [double]($durationMatch.Matches[0].Groups[1].Value)
  } else {
    $duration = [int]$Duration
  }
} catch { }

# Write a CSV summary with client-measured throughput
# Note: Client receive rate represents actual server throughput (server must send replies for client to receive them)
$csvLines = @()
$csvLines += "Test,Sent,Received,SendRate_pps,RecvRate_pps,Duration_sec,Note"
$csvLines += "LinuxEcho,$sent,$received,$sendRate,$recvRate,$duration,Client-measured (recv rate = server throughput)"
$csvLines | Out-File -FilePath "echo_summary.csv" -Encoding utf8

Write-Host "`n===== Performance Summary ====="
Write-Host "Client sent: $sent packets at $sendRate pps"
Write-Host "Client received: $received packets at $recvRate pps"
Write-Host "Server throughput (based on client receive rate): $recvRate RPS"
Write-Host "Drop rate: $(if ($sent -gt 0) { [math]::Round((1 - $received / $sent) * 100, 2) } else { 0 })%"
Write-Host "Duration: $duration seconds"
Write-Host "================================`n"

# Stop server on peer and collect logs
Write-Host "Stopping monitoring tools on peer"
if ($mpstatPid -gt 0) {
  try {
    Invoke-Command -Session $session -ScriptBlock { & /bin/kill -TERM $using:mpstatPid } | Out-Null
  } catch {
    Write-Host "Kill mpstat failed: $_"
  }
}

if ($topPid -gt 0) {
  try {
    Invoke-Command -Session $session -ScriptBlock { & /bin/kill -TERM $using:topPid } | Out-Null
  } catch {
    Write-Host "Kill top failed: $_"
  }
}

Write-Host "Stopping perf profiler on peer"
if ($perfPid -gt 0) {
  try {
    Invoke-Command -Session $session -ScriptBlock { & /bin/kill -INT $using:perfPid } | Out-Null
    Start-Sleep -Seconds 2
  } catch {
    Write-Host "Kill perf failed: $_"
  }
}

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

Write-Host "Generating perf report and fetching profiling data"
try {
  # Generate perf report on the remote machine
  Invoke-Command -Session $session -ScriptBlock {
    & /bin/bash -lc "perf report -i /tmp/server_perf.data --stdio > /tmp/server_perf_report.txt 2>&1"
    & /bin/bash -lc "perf script -i /tmp/server_perf.data > /tmp/server_perf_script.txt 2>&1"
  }
  
  Copy-Item -FromSession $session -Path '/tmp/server_perf.data' -Destination 'server_perf.data'
  Copy-Item -FromSession $session -Path '/tmp/server_perf_report.txt' -Destination 'server_perf_report.txt'
  Copy-Item -FromSession $session -Path '/tmp/server_perf_script.txt' -Destination 'server_perf_script.txt'
  Copy-Item -FromSession $session -Path '/tmp/perf.log' -Destination 'perf.log' -ErrorAction SilentlyContinue
  Copy-Item -FromSession $session -Path '/tmp/system_info.txt' -Destination 'system_info.txt' -ErrorAction SilentlyContinue
  Copy-Item -FromSession $session -Path '/tmp/mpstat.log' -Destination 'mpstat.log' -ErrorAction SilentlyContinue
  Copy-Item -FromSession $session -Path '/tmp/top.log' -Destination 'top.log' -ErrorAction SilentlyContinue
  
  # Collect post-test diagnostics
  Write-Host "Collecting post-test network diagnostics"
  Invoke-Command -Session $session -ScriptBlock {
    & /bin/bash -lc "ip addr show > /tmp/ip_addr.txt 2>&1"
    & /bin/bash -lc "ip route show > /tmp/ip_route.txt 2>&1"
    & /bin/bash -lc "cat /proc/net/dev > /tmp/proc_net_dev.txt 2>&1"
    & /bin/bash -lc "ethtool -S eth0 2>/dev/null > /tmp/ethtool_stats.txt || ethtool -S ens1 2>/dev/null > /tmp/ethtool_stats.txt || echo 'No NIC found' > /tmp/ethtool_stats.txt"
    & /bin/bash -lc "lscpu > /tmp/lscpu.txt 2>&1"
  }
  Copy-Item -FromSession $session -Path '/tmp/ip_addr.txt' -Destination 'ip_addr.txt' -ErrorAction SilentlyContinue
  Copy-Item -FromSession $session -Path '/tmp/ip_route.txt' -Destination 'ip_route.txt' -ErrorAction SilentlyContinue
  Copy-Item -FromSession $session -Path '/tmp/proc_net_dev.txt' -Destination 'proc_net_dev.txt' -ErrorAction SilentlyContinue
  Copy-Item -FromSession $session -Path '/tmp/ethtool_stats.txt' -Destination 'ethtool_stats.txt' -ErrorAction SilentlyContinue
  Copy-Item -FromSession $session -Path '/tmp/lscpu.txt' -Destination 'lscpu.txt' -ErrorAction SilentlyContinue
  
  Write-Host "Successfully fetched profiling and network data"
} catch {
  Write-Host "Failed to fetch data: $_"
}

# Close session
if ($session) { Remove-PSSession $session }

# Return non-zero if client failed
if ($clientExit -ne 0) {
  Write-Host "Client reported non-zero exit: $clientExit"
  exit $clientExit
}
