param(
  [switch]$CpuProfile,
  [string]$PeerName,
  [string]$SenderOptions,
  [string]$ReceiverOptions,
  [string]$Duration = "60"
)

Set-StrictMode -Version Latest

# Import shared utilities module
function Find-RepoRoot {
  param(
    [Parameter(Mandatory = $true)][string]$StartDir
  )

  $dir = (Resolve-Path -LiteralPath $StartDir).Path
  while ($true) {
    if (Test-Path -LiteralPath (Join-Path $dir '.git')) {
      return $dir
    }

    $parent = Split-Path -Parent $dir
    if (-not $parent -or $parent -eq $dir) {
      return $null
    }
    $dir = $parent
  }
}

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$moduleName = 'performance_utilities.psm1'
$moduleCandidates = @(
  (Join-Path $scriptDir $moduleName),
  (Join-Path $scriptDir (Join-Path '..' $moduleName)),
  (Join-Path $scriptDir (Join-Path '..\..' $moduleName))
)

if ($env:GITHUB_WORKSPACE) {
  $moduleCandidates += (Join-Path $env:GITHUB_WORKSPACE (Join-Path '.github\scripts' $moduleName))
}

$repoRoot = Find-RepoRoot -StartDir $scriptDir
if ($repoRoot) {
  $moduleCandidates += (Join-Path $repoRoot (Join-Path '.github\scripts' $moduleName))
}

$modulePath = $moduleCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $modulePath) {
  $moduleCandidatesString = ($moduleCandidates | ForEach-Object { "  $_" }) -join [Environment]::NewLine
  throw "Could not find required module '$moduleName'. Tried:${([Environment]::NewLine)}$moduleCandidatesString"
}

Import-Module $modulePath -Force

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

# Note: WPR profiling, error handling, and monitoring functions are imported from performance_utilities.psm1

function Write-Phase {
  param([Parameter(Mandatory=$true)][string]$Message)
  Write-Host "[$(Get-Date -Format o)] $Message"
}

function Wait-JobWithProgress {
  param(
    [Parameter(Mandatory=$true)]$Job,
    [Parameter(Mandatory=$true)][string]$Name,
    [int]$PollSeconds = 15
  )

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  while ($true) {
    $completed = Wait-Job -Job $Job -Timeout $PollSeconds
    if ($completed) { break }

    $state = $Job.JobStateInfo.State
    Write-Phase "Still waiting on $Name (JobId=$($Job.Id), State=$state, Elapsed=$([Math]::Round($sw.Elapsed.TotalSeconds, 0))s)"
  }

  $sw.Stop()
  $state = $Job.JobStateInfo.State
  Write-Phase "$Name completed (JobId=$($Job.Id), State=$state, Elapsed=$([Math]::Round($sw.Elapsed.TotalSeconds, 2))s)"
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
  $Job = Invoke-ToolInSession -Session $Session -RemoteDir $script:RemoteDir -ToolDir 'echo' -ToolName "echo_server" -Options $serverArgs -WaitSeconds 0

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
  $Job = Invoke-ToolInSession -Session $Session -RemoteDir $script:RemoteDir -ToolDir 'echo' -ToolName "echo_client" -Options $serverArgs -WaitSeconds 0

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
  Copy-ToolDirToRemote -Session $Session -RemoteDir $script:RemoteDir -ToolDir 'echo'

  # Launch per-CPU usage monitor as a background job (returns array of per-CPU averages)
  Write-Phase "Starting CPU/perf counter jobs (send phase)"
  $cpuMonitorJob = CaptureIndividualCpuUsagePerformanceMonitorAsJob -DurationSeconds $Duration
  $perfCounterJob = CapturePerformanceMonitorAsJob -DurationSeconds $Duration -Counters $PerformanceCounters

  # Run tests
  Write-Phase "Starting send test"
  Run-SendTest -PeerName $PeerName -Session $Session -SenderOptions $SenderOptions -ReceiverOptions $ReceiverOptions
  Write-Phase "Send test finished"

  # Recover CPU usage data (monitor returns per-CPU averages). Print per-CPU values.
  Write-Phase "Waiting for CPU monitor job (send phase)"
  Wait-JobWithProgress -Job $cpuMonitorJob -Name 'CPU monitor (send)'
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
  Write-Phase "Waiting for perf counter job (send phase)"
  Wait-JobWithProgress -Job $perfCounterJob -Name 'Perf counters (send)'
  $perfResults = Receive-Job -Job $perfCounterJob -Wait -AutoRemoveJob
  $perfJsonPath = Join-Path $cwd 'echo_client_perf_counters.json'
  $perfResults | ConvertTo-Json | Out-File -FilePath $perfJsonPath -Encoding utf8 -Force
  Write-Phase "Perf counter JSON written (send phase): $perfJsonPath"

  # Launch another per-CPU usage monitor for the recv test
  Write-Phase "Starting CPU/perf counter jobs (recv phase)"
  $cpuMonitorJob = CaptureIndividualCpuUsagePerformanceMonitorAsJob -DurationSeconds $Duration
  $perfCounterJob = CapturePerformanceMonitorAsJob -DurationSeconds $Duration -Counters $PerformanceCounters

  Write-Phase "Starting recv test"
  Run-RecvTest -PeerName $PeerName -Session $Session -SenderOptions $SenderOptions -ReceiverOptions $ReceiverOptions
  Write-Phase "Recv test finished"

  # Recover CPU usage data (monitor returns per-CPU averages). Print per-CPU values.
  Write-Phase "Waiting for CPU monitor job (recv phase)"
  Wait-JobWithProgress -Job $cpuMonitorJob -Name 'CPU monitor (recv)'
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
  Write-Phase "Waiting for perf counter job (recv phase)"
  Wait-JobWithProgress -Job $perfCounterJob -Name 'Perf counters (recv)'
  $perfResults = Receive-Job -Job $perfCounterJob -Wait -AutoRemoveJob
  $perfJsonPath = Join-Path $cwd 'echo_server_perf_counters.json'
  $perfResults | ConvertTo-Json | Out-File -FilePath $perfJsonPath -Encoding utf8 -Force
  Write-Phase "Perf counter JSON written (recv phase): $perfJsonPath"
 
  # List json files in cwd
  Write-Host "JSON files in $cwd"
  Get-ChildItem -Path $cwd -Filter *.json | ForEach-Object { Write-Host "  $($_.FullName)" }

  # Print each JSON file's contents
  Get-ChildItem -Path $cwd -Filter *.json | ForEach-Object {
    Write-Host "Contents of $($_.FullName) - "
    Get-Content -Path $_.FullName | ForEach-Object { Write-Host "  $_" }
  }

  # Copy the stats file to the parent folder for GitHub Actions artifact upload
  if (Test-Path *.json) {
    Copy-Item -Path *.json -Destination $cwd\.. -Force
  }
  else {
    Write-Host "No JSON files found to copy."
  }

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
