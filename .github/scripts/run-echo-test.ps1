param(
  [switch]$CpuProfile,
  [string]$PeerName,
  [string]$SenderOptions,
  [string]$ReceiverOptions,
  [string]$Duration = "60", # Duration in seconds for the test runs (default 60s)
  [int]$RssCpuCount = 0 # Number of CPUs to enable RSS on the remote server (0 = max available
)

Set-StrictMode -Version Latest

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
if ($Duration -and $Duration -gt 0 -and $SenderOptions -notmatch '--duration') {
  $SenderOptions += " --duration $Duration"
}

if ($Duration -and $Duration -gt 0 -and $ReceiverOptions -notmatch '--duration') {
  $ReceiverOptions += " --duration $Duration"
}

# Make errors terminate so catch can handle them
$ErrorActionPreference = 'Stop'
$Session = $null
$exitCode = 0

# Ensure local firewall state variable exists so cleanup never errors
$localFwState = $null

# Helper to parse quoted command-line option strings into an array
function Convert-ArgStringToArray($s) {
  if ([string]::IsNullOrEmpty($s)) { return @() }
  # Pattern allows quoted strings with backslash-escaped characters, or unquoted tokens
    # Matches either: "( (?: \\. | [^"\\] )* )"  or  [^"\s]+
    $pattern = '("((?:\\.|[^"\\])*)"|[^"\s]+)'
  $regexMatches = [regex]::Matches($s, $pattern)
  $out = @()
  foreach ($m in $regexMatches) {
    if ($m.Groups[2].Success) {
      # Quoted token; Group 2 contains inner text with possible escapes
      $val = $m.Groups[2].Value
      # Unescape backslash-escaped sequences commonly used in CLI args
      $val = $val -replace '\\', '\'
      $val = $val -replace '\"', '"'
    }
    else {
      # Unquoted token in Group 1
      $val = $m.Groups[1].Value
    }
    $out += $val.Trim()
  }
  return $out
}

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

# Rename a local file if it exists; ignore if not present
function Rename-LocalIfExists {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$NewName
  )
  try {
    if (Test-Path $Path) {
      # If the desired new name already exists, remove it first so Rename-Item succeeds
      if (Test-Path $NewName) {
        try { Remove-Item -Path $NewName -Force -ErrorAction Stop } catch { Write-Host "Warning: failed to remove existing '$NewName': $($_.Exception.Message)" }
      }
      Rename-Item -Path $Path -NewName $NewName -ErrorAction Stop
    }
  }
  catch {
    Write-Host "Failed to rename $Path -> $NewName $($_.Exception.Message)"
  }
}

# Print detailed information for an ErrorRecord or Exception. Supports pipeline input.
function Write-DetailedError {
  param(
    [Parameter(ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)] $InputObject
  )

  process {
    $er = $InputObject
    if ($null -eq $er) { return }
    if ($er -is [System.Management.Automation.ErrorRecord]) {
      Write-Host "ERROR: $($er.Exception.Message)"
      if ($er.Exception.StackTrace) { Write-Host "StackTrace: $($er.Exception.StackTrace)" }
      if ($er.InvocationInfo) { Write-Host "Invocation: $($er.InvocationInfo.PositionMessage)" }
      Write-Host "ErrorRecord: $er"
    }
    elseif ($er -is [System.Exception]) {
      Write-Host "EXCEPTION: $($er.Message)"
      if ($er.StackTrace) { Write-Host "StackTrace: $($er.StackTrace)" }
    }
    else {
      Write-Host $er
    }
  }
}

function Set-RssOnCpus {
    param(
        [Parameter(Mandatory=$true)][string]$TargetServer,
        [Parameter(Mandatory=$false)][int]$CpuCount
    )

    Write-Host "Checking connectivity to '$TargetServer'..."

    function Get-RssCapabilities {
        param([string]$AdapterName)

        # Prefer the convenient cmdlet if available
        if (Get-Command -Name Get-NetAdapterRssCapabilities -ErrorAction SilentlyContinue) {
            try {
                $res = Get-NetAdapterRssCapabilities -Name $AdapterName -ErrorAction SilentlyContinue
                if ($res) {
                    return [PSCustomObject]@{
                        MaxProcessorNumber = [int]$res.MaxProcessorNumber
                        MaxProcessorGroup  = [int]$res.MaxProcessorGroup
                    }
                }
                return $null
            } catch {
                return $null
            }
        }

        # Fallback: query the CIM class directly
        try {
            $filter = "Name='$AdapterName'"
            $obj = Get-CimInstance -Namespace root/StandardCimv2 -ClassName MSFT_NetAdapterRssSettingData -Filter $filter -ErrorAction SilentlyContinue
            if ($obj) {
                return [PSCustomObject]@{
                    MaxProcessorNumber = [int]$obj.MaxProcessorNumber
                    MaxProcessorGroup  = [int]$obj.MaxProcessorGroup
                }
            }
        } catch {
            # ignore
        }
        return $null
    }

    # Simple reachability test: use Test-NetConnection once. If it succeeds, pick a usable NIC.
    try {
        $result = Test-NetConnection -ComputerName $TargetServer -WarningAction SilentlyContinue
    } catch {
        $result = $null
    }

    if (-not ($result -and $result.PingSucceeded)) {
        Write-Host "Target '$TargetServer' is not reachable from this host. Returning without changes."
        return
    }

    # Choose the first 'Up' physical adapter as the target NIC
    $adapter = Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
    if (-not $adapter) {
        Write-Host "No operational physical network adapter found. Returning."
        return
    }

    $ReachableNIC = $adapter.Name
    Write-Host "Configuring RSS on adapter: $ReachableNIC"

    # Check RSS capabilities (cmdlet or CIM fallback)
    $capCheck = Get-RssCapabilities -AdapterName $ReachableNIC
    if (-not $capCheck) {
        Write-Host "Adapter '$ReachableNIC' does not expose RSS capabilities or does not support RSS. Skipping RSS configuration."
        return
    }

    # Enable RSS if the cmdlet exists; otherwise inform and continue to capability-only flow
    if (Get-Command -Name Enable-NetAdapterRss -ErrorAction SilentlyContinue) {
        try {
            Enable-NetAdapterRss -Name $ReachableNIC -ErrorAction Stop
        } catch {
            Write-Host "Failed to enable RSS on '$ReachableNIC': $($_.Exception.Message)"
            return
        }
    } else {
        Write-Host "Enable-NetAdapterRss cmdlet not present; skipping enable step."
    }

    # Get RSS capabilities to determine CPU range
    # Re-read capabilities (cmdlet or CIM fallback)
    $cap = Get-RssCapabilities -AdapterName $ReachableNIC
    if (-not $cap) {
        Write-Host "No RSS capability information returned. Returning."
        return
    }

    $maxCPU = $cap.MaxProcessorNumber
    $maxGroup = $cap.MaxProcessorGroup

    if (-not ($maxCPU -is [int]) -or -not ($maxGroup -is [int])) {
        Write-Host "Unexpected RSS capability values. Returning."
        return
    }

    if ($maxGroup -lt 1) {
        Write-Host "No processor groups reported. Assuming group 0."
        $useGroup = 0
    } else {
        $useGroup = 0
    }
    if ($maxCPU -lt 0) {
        Write-Host "Invalid MaxProcessorNumber ($maxCPU). Returning."
        return
    }

    if (Get-Command -Name Set-NetAdapterRss -ErrorAction SilentlyContinue) {
        # Determine how many CPUs to set. Use provided CpuCount if valid, otherwise the adapter max.
        if ($CpuCount) {
            if ($CpuCount -lt 1) {
                Write-Host "Provided CpuCount ($CpuCount) is invalid; must be >= 1. Returning."
                return
            }
            if ($CpuCount -gt ($maxCPU + 1)) {
                Write-Host "Provided CpuCount ($CpuCount) exceeds adapter MaxProcessorNumber ($maxCPU + 1). Clamping to max."
                $useMax = $maxCPU
            } else {
                # Convert CpuCount (count) to MaxProcessorNumber (index)
                $useMax = [int]($CpuCount - 1)
            }
        } else {
            $useMax = $maxCPU
        }

        Write-Host "Setting RSS to use CPUs 0..$useMax in group $useGroup"
        try {
            Set-NetAdapterRss -Name $ReachableNIC -BaseProcessorGroup $useGroup -MaxProcessorNumber $useMax -ErrorAction Stop
        } catch {
            Write-Host "Failed to set RSS on '$ReachableNIC': $($_.Exception.Message)"
            return
        }

        if (Get-Command -Name Get-NetAdapterRss -ErrorAction SilentlyContinue) {
            Write-Host "Updated RSS settings for '$ReachableNIC':"
            Get-NetAdapterRss -Name $ReachableNIC
        } else {
            Write-Host "Set successful (no Get-NetAdapterRss cmdlet present to display settings)."
        }
    } else {
        Write-Host "Set-NetAdapterRss cmdlet not present; cannot modify RSS settings. Displaying reported capabilities instead:"
        Write-Host "MaxProcessorNumber: $maxCPU, MaxProcessorGroup: $maxGroup"
    }
}


# function Set-RssOnAllCpu {
#   param([Parameter(Mandatory=$true)][string]$TargetServer)

#   # Get all NICs with IPv4 addresses
#   $NICs = Get-NetIPAddress | Where-Object { $_.AddressFamily -eq 'IPv4' -and $_.IPAddress -notlike '169.*' }

#   $ReachableNIC = $null

#   Write-Host "Testing connectivity to $TargetServer from each NIC..."

#   foreach ($nic in $NICs) {
#       $result = Test-NetConnection -ComputerName $TargetServer -SourceAddress $nic.IPAddress -WarningAction SilentlyContinue
#       if ($result.PingSucceeded) {
#           Write-Host "NIC '$($nic.InterfaceAlias)' with IP $($nic.IPAddress) can reach $TargetServer"
#           $ReachableNIC = $nic.InterfaceAlias
#           break
#       }
#   }

#   if (-not $ReachableNIC) {
#       Write-Host "No NIC could reach $TargetServer. Exiting."
#       exit
#   }

#   Write-Host "`nConfiguring RSS on NIC: $ReachableNIC"

#   # Enable RSS
#   Enable-NetAdapterRss -Name $ReachableNIC

#   # Get RSS capabilities to determine CPU range
#   $cap = Get-NetAdapterRssCapabilities -Name $ReachableNIC
#   $maxCPU = $cap.MaxProcessorNumber
#   $maxGroup = $cap.MaxProcessorGroup

#   # We assume group 0 exists and use its full range
#   Write-Host "Setting RSS to use all CPUs in group 0 (0..$maxCPU)"
#   Set-NetAdapterRss -Name $ReachableNIC -BaseProcessorGroup 0 -MaxProcessorNumber $maxCPU

#   # Verify settings
#   Write-Host "`nUpdated RSS settings:"
#   Get-NetAdapterRss -Name $ReachableNIC
# }

# WPR CPU profiling helpers
$script:WprProfiles = @{}

function Start-WprCpuProfile {
  param([Parameter(Mandatory=$true)][string]$Which)

  if (-not $CpuProfile) { return }

  $Workspace = $env:GITHUB_WORKSPACE
  $etlDir = Join-Path $Workspace 'ETL'
  if (-not (Test-Path $etlDir)) { New-Item -ItemType Directory -Path $etlDir | Out-Null }

  $WprProfile = Join-Path $etlDir 'cpu.wprp'

  $outFile = Join-Path $etlDir ("cpu_profile-$Which.etl")
  if (Test-Path $outFile) { Remove-Item $outFile -Force -ErrorAction SilentlyContinue }

  Write-Host "Starting WPR CPU profiling -> $outFile"
  try {
    # Check if WPR is already running to avoid the "profiles are already running" error
    $status = $null
    try {
      $status = & wpr -status 2>&1
    } catch {
      $status = $_.ToString()
    }

    if ($status -and $status -match 'profile(s)?\s+are\s+already\s+running|Profiles are already running|The profiles are already running') {
      Write-Host "WPR already running. Cancelling any existing profiles so we can start a fresh one..."
      try {
        & wpr -cancel 2>&1 | Out-Null
        Start-Sleep -Seconds 1
      }
      catch {
        Write-Host "Failed to cancel existing WPR session: $($_.Exception.Message). Proceeding to start a new profile anyway."
      }
    }

    try {
      & wpr -start $WprProfile -filemode | Out-Null
    }
    catch {
      Write-Host "wpr -start with custom profile failed: $($_.Exception.Message). Falling back to built-in CPU profile."
      try { & wpr -start CPU -filemode | Out-Null } catch { Write-Host "Fallback CPU start also failed: $($_.Exception.Message)" }
    }
    $script:WprProfiles[$Which] = $outFile
  }
  catch {
    Write-Host "Failed to start WPR: $($_.Exception.Message)"
  }
}

function Stop-WprCpuProfile {
  param([Parameter(Mandatory=$true)][string]$Which)

  if (-not $CpuProfile) { return }

  if (-not $script:WprProfiles.ContainsKey($Which)) {
    Write-Host "No WPR profile active for '$Which'"
    return
  }

  $outFile = $script:WprProfiles[$Which]
  Write-Host "Stopping WPR CPU profiling, saving to $outFile"
  try {
    # Attempt to stop WPR and save to the given file. If no profile is running, log and continue.
    try {
      & wpr -stop $outFile | Out-Null
    }
    catch {
      Write-Host "wpr -stop failed: $($_.Exception.Message). Attempting to query status..."
      try {
        $s = & wpr -status 2>&1
        Write-Host "WPR status: $s"
      } catch { }
    }
    $script:WprProfiles.Remove($Which) | Out-Null
  }
  catch {
    Write-Host "Failed to stop WPR: $($_.Exception.Message)"
  }
}


# =========================
# Remote job helpers
# =========================
function Invoke-EchoInSession {
  param($Session, $RemoteDir, $Name, $Options)

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
  } -ArgumentList $RemoteDir, $Name, $Options -AsJob -ErrorAction Stop

  return $Job
}

function Receive-JobOrThrow {
  param([Parameter(Mandatory)] $Job)

  Wait-Job $Job | Out-Null

  # Drain output (keep so we can inspect again if needed)
  $null = Receive-Job $Job -Keep

  $errs = @()
  foreach ($cj in $Job.ChildJobs) {
    if ($cj.Error -and $cj.Error.Count -gt 0) {
      $errs += $cj.Error
    }
    if ($cj.JobStateInfo.State -eq 'Failed' -and $cj.JobStateInfo.Reason) {
      $errs += $cj.JobStateInfo.Reason
    }
  }

  if ($errs.Count -gt 0) {
    foreach ($er in $errs) {
      if ($er -is [System.Management.Automation.ErrorRecord]) {
        $er | Write-DetailedError
      }
      else {
        Write-Host  $er
      }
    }
    throw "One or more remote errors occurred (job id: $($Job.Id))."
  }

  if ($Job.State -eq 'Failed') {
    throw "Remote job failed (job id: $($Job.Id)): $($Job.JobStateInfo.Reason)"
  }
}

# -------------------------
# Refactored workflow functions
# -------------------------

function Create-Session {
  param(
    [Parameter(Mandatory=$true)][string]$PeerName,
    [string]$RemotePSConfiguration = 'PowerShell.7'
  )

  $script:RemotePSConfiguration = $RemotePSConfiguration
  $script:RemoteDir = 'C:\_work'

  $Username = (Get-ItemProperty 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon').DefaultUserName
  $Password = (Get-ItemProperty 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon').DefaultPassword | ConvertTo-SecureString -AsPlainText -Force
  $Creds = New-Object System.Management.Automation.PSCredential ($Username, $Password)

  try {
    Write-Host "Creating PSSession to $PeerName using configuration '$RemotePSConfiguration'..."
    $s = New-PSSession -ComputerName $PeerName -Credential $Creds -ConfigurationName $RemotePSConfiguration -ErrorAction Stop
    Write-Host "Session created using configuration '$RemotePSConfiguration'."
  }
  catch {
    Write-Host "Failed to create session using configuration '$RemotePSConfiguration': $($_.Exception.Message)"
    Write-Host "Attempting fallback: creating session without ConfigurationName..."
    try {
      $s = New-PSSession -ComputerName $PeerName -Credential $Creds -ErrorAction Stop
      Write-Host "Session created using default configuration."
    }
    catch {
      Write-Host "Fallback session creation failed: $($_.Exception.Message)"
      throw "Failed to create remote session to $PeerName"
    }
  }

  $script:Session = $s
  return $s
}

function Save-And-Disable-Firewalls {
  param([Parameter(Mandatory=$true)]$Session)

  # Coerce possible multi-output (array) from Create-Session into the actual PSSession object.
  if ($Session -is [System.Array]) {
    $found = $Session | Where-Object { $_ -is [System.Management.Automation.Runspaces.PSSession] }
    if ($found -and $found.Count -gt 0) { $Session = $found[0] }
    else { $Session = $Session[0] }
  }

  if (-not ($Session -is [System.Management.Automation.Runspaces.PSSession])) {
    throw "Save-And-Disable-Firewalls requires a PSSession object. Got: $($Session.GetType().FullName) - $Session"
  }

  Write-Host "Saving and disabling local firewall profiles..."
  $script:localFwState = Get-NetFirewallProfile -Profile Domain, Public, Private | Select-Object Name, Enabled
  Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled False

  Write-Host "Disabling firewall on remote machine..."
  Invoke-Command -Session $Session -ScriptBlock {
    param()
    $fw = Get-NetFirewallProfile -Profile Domain, Public, Private | Select-Object Name, Enabled
    Set-Variable -Name __SavedFirewallState -Value $fw -Scope Global -Force
    Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled False
  } -ErrorAction Stop
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
  $Job = Invoke-EchoInSession -Session $Session -RemoteDir $script:RemoteDir -Name "echo_server" -Options $serverArgs

  $clientArgs = Convert-ArgStringToArray $SenderOptions
  $clientArgs = Normalize-Args -Tokens $clientArgs

  Write-Host "[Local] Running: .\echo_client.exe"
  Write-Host "[Local] Arguments:"
  foreach ($a in $clientArgs) { Write-Host "  $a" }
  Start-WprCpuProfile -Which 'send'
  & .\echo_client.exe @clientArgs
  $script:localExit = $LASTEXITCODE
  Stop-WprCpuProfile -Which 'send'

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
  $Job = Invoke-EchoInSession -Session $Session -RemoteDir $script:RemoteDir -Name "echo_client" -Options $serverArgs

  $clientArgs = Convert-ArgStringToArray $ReceiverOptions
  $clientArgs = Normalize-Args -Tokens $clientArgs

  Write-Host "[Local] Running: .\echo_server.exe"
  Write-Host "[Local] Arguments:"
  foreach ($a in $clientArgs) { Write-Host "  $a" }
  Start-WprCpuProfile -Which 'recv'
  & .\echo_server.exe @clientArgs
  $script:localExit = $LASTEXITCODE
  Stop-WprCpuProfile -Which 'recv'

  Receive-JobOrThrow -Job $Job
}

function CaptureIndividualCpuUsagePerformanceMonitorAsJob {
  param(
    [Parameter(Mandatory=$true)][string]$DurationSeconds
  )

  # Ensure we pass a numeric duration into the job and use that value inside
  $intDuration = [int]::Parse($DurationSeconds)

  $cpuMonitorJob = Start-Job -ScriptBlock {
    param($duration)

    # Use the Processor Information counter which contains CPU instances across all groups
    # (e.g., "0,0", "0,1", "1,0" etc.) so we capture CPUs from every group, not just group 0.
    $counter = '\Processor Information(*)\% Processor Time'
    $d = [int]$duration

    try {
      $samples = Get-Counter -Counter $counter -SampleInterval 1 -MaxSamples $d -ErrorAction Stop
      # Group samples by instance (processor information name) and compute average per instance.
      # InstanceName for Processor Information uses formats like "0,0" (group,index) or descriptive names.
      $grouped = $samples.CounterSamples | Group-Object -Property InstanceName
      $results = @()
      foreach ($g in $grouped) {
        $instName = $g.Name
        # Normalize instance names: skip the _Total instance and any empty names
        if ([string]::IsNullOrEmpty($instName) -or $instName -eq '_Total') { continue }
        $vals = $g.Group | ForEach-Object { [double]$_.CookedValue }
        $avg = ($vals | Measure-Object -Average).Average
        $results += [PSCustomObject]@{ Processor = $instName; Average = $avg }
      }
      # Sort by numeric ordering where possible, otherwise by name for consistent output
      $sorted = $results | Sort-Object @{Expression={
          $n = $_.Processor -replace '[^0-9,]',''
          # If the processor string contains a comma (group,index), split and compute a sortable key
          if ($n -match ',') { $parts = $n -split ','; return ([int]$parts[0]*1000 + [int]$parts[1]) }
          if ($n -match '^[0-9]+$') { return [int]$n }
          return $_.Processor
        }},Processor
      # Emit numeric array of per-CPU numeric averages
      $numeric = $sorted | ForEach-Object { [double]$_.Average }
    }
    catch {
      $numeric = @(0)
    }

    # Emit the numeric array so the caller receives per-CPU averages
    Write-Output $numeric
  } -ArgumentList $intDuration

  return $cpuMonitorJob
}


function Restore-FirewallAndCleanup {
  param([object]$Session)

  try {
    if ($null -ne $Session) {
      try {
        Write-Host "Restoring firewall state on remote machine..."
        Invoke-Command -Session $Session -ScriptBlock {
          if (Get-Variable -Name __SavedFirewallState -Scope Global -ErrorAction SilentlyContinue) {
            $saved = Get-Variable -Name __SavedFirewallState -Scope Global -ValueOnly
            foreach ($p in $saved) {
              Set-NetFirewallProfile -Profile $p.Name -Enabled $p.Enabled
            }
            Remove-Variable -Name __SavedFirewallState -Scope Global -ErrorAction SilentlyContinue
          }
          else {
            Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled True
          }
        } -ErrorAction SilentlyContinue
      }
      catch {
        $_ | Write-DetailedError
      }

      try {
        Remove-PSSession $Session -ErrorAction SilentlyContinue
      }
      catch {
        $_ | Write-DetailedError
      }
    }

    Write-Host "Restoring local firewall state..."
    if ($localFwState) {
      foreach ($p in $localFwState) {
        Set-NetFirewallProfile -Profile $p.Name -Enabled $p.Enabled
      }
    }
    else {
      Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled True
    }
  }
  catch {
    $_ | Write-DetailedError
  }
}

# =========================
# Main workflow
# =========================
try {
  
  # Print the current working directory
  $cwd = (Get-Location).Path
  Write-Host "Current working directory: $cwd"

  Set-RssOnCpus -TargetServer $PeerName -CpuCount $RssCpuCount
  
  # Create remote session
  $Session = Create-Session -PeerName $PeerName -RemotePSConfiguration 'PowerShell.7'

  # Save and disable firewalls
  Save-And-Disable-Firewalls -Session $Session

  # Copy tool to remote
  Copy-EchoToRemote -Session $Session

  # Launch per-CPU usage monitor as a background job (returns array of per-CPU averages)
  $cpuMonitorJob = CaptureIndividualCpuUsagePerformanceMonitorAsJob $Duration

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

  # Launch another per-CPU usage monitor for the recv test
  $cpuMonitorJob = CaptureIndividualCpuUsagePerformanceMonitorAsJob $Duration

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
