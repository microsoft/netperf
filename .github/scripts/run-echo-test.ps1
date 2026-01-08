param(
  [switch]$CpuProfile,
  [string]$PeerName,
  [string]$SenderOptions,
  [string]$ReceiverOptions,
  [string]$Duration = "60"
)

Set-StrictMode -Version Latest

# Import shared utilities module
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $scriptDir 'performance_utilities.psm1') -Force

# Write out the parameters for logging
Write-Host "Parameters:"
Write-Host "  CpuProfile: $CpuProfile"
Write-Host "  PeerName: $PeerName"
Write-Host "  SenderOptions: $SenderOptions"
Write-Host "  ReceiverOptions: $ReceiverOptions"

# Add --server to the sender/client options if not already present
if ($SenderOptions -notmatch '--server') {
  $SenderOptions += " --server $PeerName"
}

# Add duration option if specified and not already present to both sender and receiver
# Convert string to int for proper numeric comparison
$durationInt = 0
if ($Duration -and [int]::TryParse($Duration, [ref]$durationInt) -and $durationInt -gt 0) {
  if ($SenderOptions -notmatch '--duration') {
    $SenderOptions += " --duration $Duration"
  }
  if ($ReceiverOptions -notmatch '--duration') {
    $ReceiverOptions += " --duration $Duration"
  }
}

# Make errors terminate so catch can handle them
$ErrorActionPreference = 'Stop'
$Session = $null
$exitCode = 0

# Ensure local firewall state variable exists so cleanup never errors
$localFwState = $null

# Normalize tokens: prefix '-' only for standalone tokens that don't look like values
function Normalize-Args {
  param([Parameter(Mandatory=$true)][object[]]$Tokens)
  if ($null -eq $Tokens) { return @() }
  $out = @()
  for ($i = 0; $i -lt $Tokens.Count; $i++) {
    $t = $Tokens[$i]
    if ([string]::IsNullOrEmpty($t)) { continue }

    # Keep tokens that already start with '-' or contain '=' as-is
    if ($t -like '-*' -or $t -match '=') {
      $out += $t
      continue
    }

    # If previous token exists and starts with '-', treat this token as that option's value
    if ($i -gt 0 -and ($Tokens[$i-1] -is [string]) -and ($Tokens[$i-1] -like '-*')) {
      $out += $t
      continue
    }

    # Otherwise prefix a single '-'
    $out += ('-' + $t)
  }
  return $out
}

# Note: WPR profiling, error handling, and monitoring functions are imported from performance_utilities.psm1

# =========================
# Remote job helpers
# =========================
function Invoke-EchoInSession {
  param($Session, $RemoteDir, $Name, $Options, $WaitSeconds = 0)

  $Job = Invoke-Command -Session $Session -ScriptBlock {
    param($RemoteDir, $Name, $Options, $WaitSeconds)

    Set-Location (Join-Path $RemoteDir 'echo')

    $Tool = Join-Path $RemoteDir ("echo\$Name.exe")
    Write-Host "[Remote] Running: $Tool"
    if ($Options -is [System.Array]) {
      Write-Host "[Remote] Arguments (array):"
      foreach ($arg in $Options) { Write-Host "  $arg" }
      $argList = $Options
    }
    else {
      Write-Host "[Remote] Arguments (string):"
      Write-Host "  $Options"
      $argList = @()
      if (-not [string]::IsNullOrEmpty($Options)) { $argList = @($Options) }
    }
    
    try {
      # Invoke the tool directly. When a timeout is requested, run the invocation
      # inside a PowerShell background job so we can enforce a timeout and cancel
      # the job (and any matching process) if it doesn't finish in time.
      if ($WaitSeconds -and $WaitSeconds -gt 0) {
        Write-Host "[Remote] Starting tool as background job for timeout control..."
        $jobScript = {
          param($ToolPath, $ArgList)
          if ($ArgList -is [System.Array]) {
            & $ToolPath @ArgList
          }
          elseif (-not [string]::IsNullOrEmpty($ArgList)) {
            & $ToolPath $ArgList
          }
          else {
            & $ToolPath
          }
          return $LASTEXITCODE
        }

        $j = Start-Job -ScriptBlock $jobScript -ArgumentList $Tool, $argList -ErrorAction Stop
        Write-Host "[Remote] Started job Id=$($j.Id)"

        # Wait-Job uses seconds for timeout
        $completed = $j | Wait-Job 
        $output = Receive-Job $j -Keep
        # The job returns the tool's exit code as the last object
        $rc = $output | Where-Object { ($_ -is [int]) -or ($_ -match '^[0-9]+$') } | Select-Object -Last 1
        if ($rc -eq $null) { $rc = 0 }
        Write-Host "[Remote] Process (job) exited with code $rc"
        if ($rc -ne 0) { throw "Remote $Tool.exe exited with code $rc" }
      }
      else {
        Write-Host "[Remote] Running tool in foreground (no timeout)..."
        if ($argList -is [System.Array]) { & $Tool @argList } elseif (-not [string]::IsNullOrEmpty($argList)) { & $Tool $argList } else { & $Tool }
        Write-Host "[Remote] Process exited with code $LASTEXITCODE"
        if ($LASTEXITCODE -ne 0) { throw "Remote $Tool.exe exited with code $LASTEXITCODE" }
      }
    }
    catch {
      throw "Failed to launch or monitor process $Tool $($_.Exception.Message)"
    }
  } -ArgumentList $RemoteDir, $Name, $Options, $WaitSeconds -AsJob -ErrorAction Stop

  return $Job
}

function Copy-EchoToRemote {
  param([Parameter(Mandatory=$true)]$Session)
  # Ensure the remote base directory and the 'echo' subdirectory both exist,
  # then copy the *contents* of the local directory into the remote folder.
  Invoke-Command -Session $Session -ScriptBlock {
    param($base, $sub)
    if (-not (Test-Path $base)) { New-Item -ItemType Directory -Path $base | Out-Null }
    $full = Join-Path $base $sub
    if (-not (Test-Path $full)) { New-Item -ItemType Directory -Path $full | Out-Null }
  } -ArgumentList $script:RemoteDir, 'echo' -ErrorAction Stop

  $localPath = (Resolve-Path .).Path
  Copy-Item -ToSession $Session -Path (Join-Path $localPath '*') -Destination "$script:RemoteDir\echo" -Recurse -Force
}

# Robust remote file fetch: try Copy-Item -FromSession, fall back to Invoke-Command/Get-Content
function Fetch-RemoteFile {
  param(
    [Parameter(Mandatory=$true)]$Session,
    [Parameter(Mandatory=$true)][string]$RemotePath,
    [Parameter(Mandatory=$true)][string]$LocalDestination
  )

  Write-Host "Fetching remote file '$RemotePath' to local '$LocalDestination'..."

  try {
    Copy-Item -FromSession $Session -Path $RemotePath -Destination $LocalDestination -ErrorAction Stop
    Write-Host "Successfully fetched remote file '$RemotePath' to '$LocalDestination' via Copy-Item -FromSession."
    return $true
  }
  catch {
    Write-Host "Copy-Item -FromSession failed for '$RemotePath': $($_.Exception.Message). Attempting Invoke-Command fallback..."
    try {
      $content = Invoke-Command -Session $Session -ScriptBlock { param($p) Get-Content -Path $p -Raw -ErrorAction Stop } -ArgumentList $RemotePath -ErrorAction Stop
      if ($null -ne $content) {
        $content | Out-File -FilePath $LocalDestination -Encoding utf8 -Force
        return $true
      }
      else {
        Write-Host "Invoke-Command returned no content for '$RemotePath'"
        return $false
      }
    }
    catch {
      Write-Host "Failed to fetch remote file '$RemotePath' via Invoke-Command: $($_.Exception.Message)"
      return $false
    }
  }
}

function Run-SendTest {
  param(
    [Parameter(Mandatory=$true)][string]$PeerName,
    [Parameter(Mandatory=$true)]$Session,
    [Parameter(Mandatory=$true)][string]$SenderOptions,
    [Parameter(Mandatory=$true)][string]$ReceiverOptions
  )

  $serverArgs = Convert-ArgStringToArray $ReceiverOptions
  # Normalize server args
  $serverArgs = Normalize-Args -Tokens $serverArgs
  Write-Host "[Local->Remote] Invoking remote job with arguments:"
  if ($serverArgs -is [System.Array]) { foreach ($arg in $serverArgs) { Write-Host "  $arg" } } else { Write-Host "  $serverArgs" }
  $Job = Invoke-EchoInSession -Session $Session -RemoteDir $script:RemoteDir -Name "echo_server" -Options $serverArgs -WaitSeconds 0

  $clientArgs = Convert-ArgStringToArray $SenderOptions
  $clientArgs = Normalize-Args -Tokens $clientArgs

  $clientArgs += @('--stats-file', 'echo_client_stats.json')

  Write-Host "[Local] Running: .\echo_client.exe"
  Write-Host "[Local] Arguments:"
  foreach ($a in $clientArgs) { Write-Host "  $a" }
  Start-WprCpuProfile -Which 'send' -CpuProfile:$CpuProfile
  & .\echo_client.exe @clientArgs
  $script:localExit = $LASTEXITCODE
  Stop-WprCpuProfile -Which 'send' -CpuProfile:$CpuProfile

  Receive-JobOrThrow -Job $Job
}

function Run-RecvTest {
  param(
    [Parameter(Mandatory=$true)][string]$PeerName,
    [Parameter(Mandatory=$true)]$Session,
    [Parameter(Mandatory=$true)][string]$SenderOptions,
    [Parameter(Mandatory=$true)][string]$ReceiverOptions
  )

  $serverArgs = Convert-ArgStringToArray $SenderOptions
  $serverArgs = Normalize-Args -Tokens $serverArgs
  Write-Host "[Local->Remote] Invoking remote job with arguments:"
  if ($serverArgs -is [System.Array]) { foreach ($arg in $serverArgs) { Write-Host "  $arg" } } else { Write-Host "  $serverArgs" }
  $Job = Invoke-EchoInSession -Session $Session -RemoteDir $script:RemoteDir -Name "echo_client" -Options $serverArgs -WaitSeconds 0

  $clientArgs = Convert-ArgStringToArray $ReceiverOptions
  $clientArgs = Normalize-Args -Tokens $clientArgs

  Write-Host "[Local] Running: .\echo_server.exe"
  Write-Host "[Local] Arguments:"
  foreach ($a in $clientArgs) { Write-Host "  $a" }
  Start-WprCpuProfile -Which 'recv' -CpuProfile:$CpuProfile
  & .\echo_server.exe @clientArgs
  $script:localExit = $LASTEXITCODE
  Stop-WprCpuProfile -Which 'recv' -CpuProfile:$CpuProfile

  Receive-JobOrThrow -Job $Job
}

$PerformanceCounters = 
@(
  '\UDPv4\Datagrams Received Errors',
  '\UDPv6\Datagrams Received Errors',

  '\Network Interface(*)\Packets Received Errors',
  '\Network Interface(*)\Packets Received Discarded',
  '\Network Interface(*)\Packets Outbound Discarded',

  '\IPv4\Datagrams Received Discarded',
  '\IPv4\Datagrams Received Header Errors',
  '\IPv4\Datagrams Received Address Errors',

  '\IPv6\Datagrams Received Discarded',
  '\IPv6\Datagrams Received Header Errors',
  '\IPv6\Datagrams Received Address Errors',

  '\WFPv4\Packets Discarded/sec',
  '\WFPv6\Packets Discarded/sec',
  '\Processor Information(*)\% Processor Time'
)

# =========================
# Main workflow
# =========================
try {
  
  # Print the current working directory with timestamp
  $cwd = (Get-Location).Path
  Write-Host "[$(Get-Date -Format o)] Current working directory: $cwd"

  Get-NetAdapterRss

  Write-Host "[$(Get-Date -Format o)] Starting echo tests to peer '$PeerName' with duration $Duration seconds..."

  # Create remote session
  $Session = Create-Session -PeerName $PeerName -RemotePSConfiguration 'PowerShell.7'

  # Initialize script-level variables used by helper functions
  $script:RemoteDir = 'C:\_work'
  $script:RemotePSConfiguration = 'PowerShell.7'

  # Save and disable firewalls
  Save-And-Disable-Firewalls -Session $Session

  # Copy tool to remote
  Copy-EchoToRemote -Session $Session

  # Launch per-CPU usage monitor as a background job (returns array of per-CPU averages)
  $cpuMonitorJob = CaptureIndividualCpuUsagePerformanceMonitorAsJob -DurationSeconds $Duration
  $perfCounterJob = CapturePerformanceMonitorAsJob -DurationSeconds $Duration -Counters $PerformanceCounters

  # Run tests
  Run-SendTest -PeerName $PeerName -Session $Session -SenderOptions $SenderOptions -ReceiverOptions $ReceiverOptions

  # Recover CPU usage data (monitor returns per-CPU averages). Print per-CPU values.
  $cpuUsagePerCpu = Receive-Job -Job $cpuMonitorJob -Wait -AutoRemoveJob
  if ($cpuUsagePerCpu -is [System.Array]) {
    $i = 0
    foreach ($val in $cpuUsagePerCpu) {
      $i++
      Write-Host "CPU$i $([math]::Round([double]$val, 2)) %"
    }
    # Compute and print overall average across all CPUs
    $overall = (($cpuUsagePerCpu | Measure-Object -Average).Average)
    Write-Host "Overall average CPU Usage: $([math]::Round($overall, 2)) %"
  }
  else {
    Write-Host "CPU1 $([math]::Round([double]$cpuUsagePerCpu, 2)) %"
  }

  # Write the performance counter results as a JSON file
  $perfResults = Receive-Job -Job $perfCounterJob -Wait -AutoRemoveJob
  $perfJsonPath = Join-Path $cwd 'echo_client_perf_counters.json'
  $perfResults | ConvertTo-Json | Out-File -FilePath $perfJsonPath -Encoding utf8 -Force

  # Launch another per-CPU usage monitor for the recv test
  $cpuMonitorJob = CaptureIndividualCpuUsagePerformanceMonitorAsJob -DurationSeconds $Duration
  $perfCounterJob = CapturePerformanceMonitorAsJob -DurationSeconds $Duration -Counters $PerformanceCounters

  Run-RecvTest -PeerName $PeerName -Session $Session -SenderOptions $SenderOptions -ReceiverOptions $ReceiverOptions

  # Recover CPU usage data (monitor returns per-CPU averages). Print per-CPU values.
  $cpuUsagePerCpu = Receive-Job -Job $cpuMonitorJob -Wait -AutoRemoveJob
  if ($cpuUsagePerCpu -is [System.Array]) {
    $i = 0
    foreach ($val in $cpuUsagePerCpu) {
      $i++
      Write-Host "CPU$i $([math]::Round([double]$val, 2)) %"
    }
    # Compute and print overall average across all CPUs
    $overall = (($cpuUsagePerCpu | Measure-Object -Average).Average)
    Write-Host "Overall average CPU Usage: $([math]::Round($overall, 2)) %"
  }
  else {
    Write-Host "CPU1 $([math]::Round([double]$cpuUsagePerCpu, 2)) %"
  }

  # Write the performance counter results as a JSON file
  $perfResults = Receive-Job -Job $perfCounterJob -Wait -AutoRemoveJob
  $perfJsonPath = Join-Path $cwd 'echo_server_perf_counters.json'
  $perfResults | ConvertTo-Json | Out-File -FilePath $perfJsonPath -Encoding utf8 -Force
 
  # List json files in cwd
  Write-Host "JSON files in $cwd"
  Get-ChildItem -Path $cwd -Filter *.json | ForEach-Object { Write-Host "  $($_.FullName)" }

  # Print each JSON file's contents
  Get-ChildItem -Path $cwd -Filter *.json | ForEach-Object {
    Write-Host "Contents of $($_.FullName) - "
    Get-Content -Path $_.FullName | ForEach-Object { Write-Host "  $_" }
  }

  # Copy the stats file to the parent folder for GitHub Actions artifact upload
  Copy-Item -Path *.json -Destination $cwd\.. -Force

  Write-Host "echo tests completed successfully."
}
catch {
  # $_ is an ErrorRecord; print everything useful
  Write-Host "echo tests failed."
  Write-Host $_
  $exitCode = 2
}
finally {
    # Use refactored cleanup function
    Restore-FirewallAndCleanup -Session $Session
    Write-Host "Exiting with code $exitCode"
    exit $exitCode
}

<#
  Troubleshooting notes for PowerShell Remoting errors:

  - Add remote host to TrustedHosts (run as Administrator on the client):
    ```powershell
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value "alanjo-test-2" -Force
    # or allow all (less secure):
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
    ```

  - Enable WinRM on the remote machine (run as Administrator on the remote):
    ```powershell
    Enable-PSRemoting -Force
    # Ensure the WinRM service is running:
    Set-Service WinRM -StartupType Automatic
    Start-Service WinRM
    ```

  - If using PowerShell 7 session configuration, register it on the remote (run on remote machine in PowerShell 7):
    ```powershell
    # Register a PowerShell 7 endpoint named 'PowerShell.7'
    Register-PSSessionConfiguration -Name PowerShell.7 -RunAsCredential (Get-Credential) -Force
    # Or use pwsh's implicit registration helper if available:
    # pwsh -NoProfile -Command "Register-PSSessionConfiguration -Name PowerShell.7 -Force"
    ```

  - For HTTPS transport, create an HTTPS listener and configure an SSL cert for WinRM on the remote. See `about_Remote_Troubleshooting`.

  Note: Adding hosts to TrustedHosts weakens authentication; prefer HTTPS or domain-joined Kerberos where possible.
  #>
