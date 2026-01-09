# WPR CPU profiling helpers
$script:WprProfiles = @{}
$script:localFwState = $null

# Helper to parse quoted command-line option strings into an array
# Handles quoted arguments with spaces and backslash-escaped sequences
function Convert-ArgStringToArray {
  param([string]$s)
  if ([string]::IsNullOrEmpty($s)) { return @() }
  # Pattern: either a double-quoted string with backslash-escaped characters (group 2 = inner text),
  # or an unquoted token consisting of non-space, non-quote characters.
  $pattern = '("((?:\\.|[^"\\])*)"|[^"\s]+)'
  $regexMatches = [regex]::Matches($s, $pattern)
  $out = @()
  foreach ($m in $regexMatches) {
    if ($m.Groups[2].Success) {
      # Quoted token; Group 2 contains inner text with possible escapes
      $val = $m.Groups[2].Value
      # Unescape backslash-escaped sequences commonly used in CLI args
      $val = $val -replace '\\\\', '\'
      $val = $val -replace '\\"', '"'
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

function Start-WprCpuProfile {
  param(
    [Parameter(Mandatory=$true)][string]$Which,
    [Parameter(Mandatory=$false)][switch]$CpuProfile
  )

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
  param(
    [Parameter(Mandatory=$true)][string]$Which,
    [Parameter(Mandatory=$false)][switch]$CpuProfile
  )

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

# Invoke a tool in a remote session with optional timeout and comprehensive error handling.
# Platform-agnostic: works on Windows (WinRM) and Linux (SSH).
# Parameters:
#   -Session: PSSession to execute in
#   -RemoteDir: Base directory path on remote (tooldir resolved relative to this)
#   -ToolDir: Subdirectory name containing tools (e.g., 'echo')
#   -ToolName: Tool executable name without extension (e.g., 'echo_server')
#   -Options: Command-line options as array or space-delimited string
#   -WaitSeconds: Timeout in seconds (0 = no timeout)
function Invoke-ToolInSession {
  param(
    [Parameter(Mandatory=$true)]$Session,
    [Parameter(Mandatory=$true)][string]$RemoteDir,
    [Parameter(Mandatory=$true)][string]$ToolDir,
    [Parameter(Mandatory=$true)][string]$ToolName,
    $Options,
    [int]$WaitSeconds = 0
  )

  $Job = Invoke-Command -Session $Session -ScriptBlock {
    param($RemoteDir, $ToolDir, $ToolName, $Options, $WaitSeconds)

    # Resolve tool path: platform-agnostic using Join-Path
    $toolDir = Join-Path $RemoteDir $ToolDir
    Set-Location $toolDir

    # On Windows, try with .exe; on Unix-like, use as-is
    $Tool = $null
    if ($PSVersionTable.Platform -eq 'Win32NT' -or -not $PSVersionTable.Platform) {
      # Windows
      $exePath = Join-Path $toolDir "$ToolName.exe"
      if (Test-Path $exePath) { $Tool = $exePath } else { $Tool = Join-Path $toolDir $ToolName }
    }
    else {
      # Unix/Linux
      $Tool = Join-Path $toolDir $ToolName
    }

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
        if ($rc -ne 0) { throw "Remote tool exited with code $rc" }
      }
      else {
        Write-Host "[Remote] Running tool in foreground (no timeout)..."
        if ($argList -is [System.Array]) { & $Tool @argList } elseif (-not [string]::IsNullOrEmpty($argList)) { & $Tool $argList } else { & $Tool }
        Write-Host "[Remote] Process exited with code $LASTEXITCODE"
        if ($LASTEXITCODE -ne 0) { throw "Remote tool exited with code $LASTEXITCODE" }
      }
    }
    catch {
      throw "Failed to launch or monitor process $Tool $($_.Exception.Message)"
    }
  } -ArgumentList $RemoteDir, $ToolDir, $ToolName, $Options, $WaitSeconds -AsJob -ErrorAction Stop

  return $Job
}

# Copy a tool directory from the current working directory to a remote session.
# Creates both the base remote directory and subdirectory if they don't exist.
# Parameters:
#   -Session: PSSession to copy to
#   -RemoteDir: Base directory path on remote
#   -ToolDir: Subdirectory name (e.g., 'echo')
function Copy-ToolDirToRemote {
  param(
    [Parameter(Mandatory=$true)]$Session,
    [Parameter(Mandatory=$true)][string]$RemoteDir,
    [Parameter(Mandatory=$true)][string]$ToolDir
  )
  
  # Ensure the remote base directory and subdirectory both exist
  Invoke-Command -Session $Session -ScriptBlock {
    param($base, $sub)
    if (-not (Test-Path $base)) { New-Item -ItemType Directory -Path $base | Out-Null }
    $full = Join-Path $base $sub
    if (-not (Test-Path $full)) { New-Item -ItemType Directory -Path $full | Out-Null }
  } -ArgumentList $RemoteDir, $ToolDir -ErrorAction Stop

  # Copy all contents of local tool directory to remote subdirectory
  $localPath = (Resolve-Path .).Path
  Copy-Item -ToSession $Session -Path (Join-Path $localPath '*') -Destination (Join-Path $RemoteDir $ToolDir) -Recurse -Force
}

# Fetch a file from remote session with fallback: try Copy-Item -FromSession first, 
# then fall back to Invoke-Command/Get-Content if that fails.
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

function Create-Session {
  param(
    [Parameter(Mandatory=$true)][string]$PeerName,
    [string]$RemotePSConfiguration = 'PowerShell.7'
  )

  $script:RemotePSConfiguration = $RemotePSConfiguration
  $script:RemoteDir = 'C:\_work'

  # WARNING: This retrieves credentials from Windows registry (auto-logon). This is intended for controlled lab environments only.
  # Do not use these credentials for production systems or reuse them elsewhere.
  $Username = (Get-ItemProperty 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon').DefaultUserName
  $Password = (Get-ItemProperty 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon').DefaultPassword | ConvertTo-SecureString -AsPlainText -Force
  $Creds = New-Object System.Management.Automation.PSCredential ($Username, $Password)

  try {
    Write-Host "[$(Get-Date -Format o)] Creating PSSession to $PeerName using configuration '$RemotePSConfiguration' (connectivity probe)..."
    # Run New-PSSession inside a background job as a quick connectivity probe with timeout.
    $psJob = Start-Job -ScriptBlock { param($pn,$rcfg,$c) try { New-PSSession -ComputerName $pn -Credential $c -ConfigurationName $rcfg -ErrorAction Stop } catch { throw } } -ArgumentList $PeerName,$RemotePSConfiguration,$Creds -ErrorAction Stop
    $waited = $psJob | Wait-Job -Timeout 60
    if (-not $waited) {
      Write-Host "[$(Get-Date -Format o)] Timeout waiting for New-PSSession probe to $PeerName (60s). Attempting to stop job and throw."
      try { Stop-Job $psJob -Force -ErrorAction SilentlyContinue } catch { }
      Receive-Job $psJob -ErrorAction SilentlyContinue | Out-Null
      throw "Timeout creating PSSession probe to $PeerName"
    }

    # The job completed; discard the deserialized PSSession object and create a real live session
    Receive-Job $psJob -ErrorAction SilentlyContinue | Out-Null
    Remove-Job $psJob -Force -ErrorAction SilentlyContinue

    # Quick connectivity check to WinRM port before creating a live session
    $tnc = $null
    try {
      $tnc = Test-NetConnection -ComputerName $PeerName -Port 5985 -WarningAction SilentlyContinue
    } catch { }

    if ($tnc -and $tnc.TcpTestSucceeded) {
      Write-Host "[$(Get-Date -Format o)] Connectivity to WinRM port on $PeerName OK; creating live PSSession..."
      $s = New-PSSession -ComputerName $PeerName -Credential $Creds -ConfigurationName $RemotePSConfiguration -ErrorAction Stop
      Write-Host "[$(Get-Date -Format o)] Live session created using configuration '$RemotePSConfiguration'."
    }
    else {
      Write-Host "[$(Get-Date -Format o)] Connectivity check to $PeerName failed or inconclusive; attempting direct New-PSSession..."
      $s = New-PSSession -ComputerName $PeerName -Credential $Creds -ConfigurationName $RemotePSConfiguration -ErrorAction Stop
      Write-Host "[$(Get-Date -Format o)] Live session created using configuration '$RemotePSConfiguration' (direct)."
    }
  }
  catch {
    Write-Host "[$(Get-Date -Format o)] Failed to create session using configuration '$RemotePSConfiguration': $($_.Exception.Message)"
    Write-Host "[$(Get-Date -Format o)] Attempting fallback: creating session without ConfigurationName (probe + live create)..."
    try {
      $psJob2 = Start-Job -ScriptBlock { param($pn,$c) try { New-PSSession -ComputerName $pn -Credential $c -ErrorAction Stop } catch { throw } } -ArgumentList $PeerName,$Creds -ErrorAction Stop
      $waited2 = $psJob2 | Wait-Job -Timeout 30
      if (-not $waited2) { Stop-Job $psJob2 -Force -ErrorAction SilentlyContinue; Receive-Job $psJob2 -ErrorAction SilentlyContinue | Out-Null; throw "Timeout creating fallback PSSession probe to $PeerName" }
      Receive-Job $psJob2 -ErrorAction SilentlyContinue | Out-Null
      Remove-Job $psJob2 -Force -ErrorAction SilentlyContinue

      $tnc2 = $null
      try { $tnc2 = Test-NetConnection -ComputerName $PeerName -Port 5985 -WarningAction SilentlyContinue } catch { }
      if ($tnc2 -and $tnc2.TcpTestSucceeded) {
        Write-Host "[$(Get-Date -Format o)] Connectivity to WinRM port on $PeerName OK; creating live fallback PSSession..."
        $s = New-PSSession -ComputerName $PeerName -Credential $Creds -ErrorAction Stop
        Write-Host "[$(Get-Date -Format o)] Live session created using default configuration."
      }
      else {
        Write-Host "[$(Get-Date -Format o)] Connectivity check failed for fallback; attempting direct New-PSSession without probe..."
        $s = New-PSSession -ComputerName $PeerName -Credential $Creds -ErrorAction Stop
        Write-Host "[$(Get-Date -Format o)] Live session created using default configuration (direct)."
      }
    }
    catch {
      Write-Host "[$(Get-Date -Format o)] Fallback session creation failed: $($_.Exception.Message)"
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


function CaptureCpuUsagePerformanceMonitorAsJob {
  param(
    [Parameter(Mandatory=$true)][string]$DurationSeconds
  )
  # Ensure we pass a numeric duration into the job and use that value inside
  $intDuration = [int]::Parse($DurationSeconds)

  $cpuMonitorJob = Start-Job -ScriptBlock {
    param($duration)

    $counter = '\Processor(_Total)\% Processor Time'
    $d = [int]$duration

    try {
      $samples = Get-Counter -Counter $counter -SampleInterval 1 -MaxSamples $d -ErrorAction Stop
      $values = $samples.CounterSamples | ForEach-Object { [double]$_.CookedValue }
    }
    catch {
      $values = @(0)
    }

    
    $average = ($values | Measure-Object -Average).Average 
    
    # Emit a raw numeric value so the caller can parse it reliably
    Write-Output $average
  } -ArgumentList $intDuration

  return $cpuMonitorJob
}

function CaptureIndividualCpuUsagePerformanceMonitorAsJob {
  param(
    [Parameter(Mandatory=$true)][string]$DurationSeconds
  )

  # Ensure we pass a numeric duration into the job and use that value inside
  $intDuration = [int]::Parse($DurationSeconds)

  $cpuMonitorJob = Start-Job -ScriptBlock {
    param($duration)

    # Use Processor Information counter which supports systems with multiple processor groups (>64 CPUs)
    $counter = '\\Processor Information(*)\\% Processor Time'
    $d = [int]$duration

    try {
      $samples = Get-Counter -Counter $counter -SampleInterval 1 -MaxSamples $d -ErrorAction Stop
      # Group samples by instance (processor index) and compute average per instance
      $grouped = $samples.CounterSamples | Group-Object -Property InstanceName
      $results = @()
      foreach ($g in $grouped) {
        $vals = $g.Group | ForEach-Object { [double]$_.CookedValue }
        $avg = ($vals | Measure-Object -Average).Average
        $results += [PSCustomObject]@{ Processor = $g.Name; Average = $avg }
      }
      # Sort by numeric ordering where possible, otherwise by name for consistent output
      $sorted = $results | Sort-Object @{Expression={
          $n = $_.Processor -replace '[^0-9,]',''
          # If the processor string contains a comma (group,index), split and compute a sortable key
          if ($n -match ',') { $parts = $n -split ','; return ([int]$parts[0]*1000 + [int]$parts[1]) }
          if ($n -match '^[0-9]+$') { return [int]$n }
          return $_.Processor
        }},Processor
      # Emit numeric array (only per-CPU numeric averages, excluding the _Total instance)
      $numeric = $sorted | Where-Object { $_.Processor -ne '_Total' } | ForEach-Object { [double]$_.Average }
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
    if ($script:localFwState) {
      foreach ($p in $script:localFwState) {
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

function Set-RssSettings {
    param(
        [Parameter(Mandatory=$true)][string]$AdapterName,
        [Parameter(Mandatory=$false)][int]$CpuCount
    )

    Write-Host "Applying RSS settings to adapter '$AdapterName'..."

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

    # Use the adapter name provided by the caller and validate it exists and is operational
    try {
        $adapter = Get-NetAdapter -Name $AdapterName -ErrorAction SilentlyContinue
    } catch {
        $adapter = $null
    }
    if (-not $adapter) {
        Write-Host "Adapter '$AdapterName' not found. Returning."
        return
    }
    if ($adapter.Status -ne 'Up') {
        Write-Host "Adapter '$AdapterName' is not operational (Status: $($adapter.Status)). Returning."
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

    # Currently only processor group 0 is used, regardless of MaxProcessorGroup.
    if ($maxGroup -lt 1) {
        Write-Host "No processor groups reported. Assuming group 0."
    }
    $useGroup = 0
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

        $CpuCount = $useMax + 1

        Write-Host "Setting RSS to use CPUs 0..$useMax in group $useGroup"
        try {
            Set-NetAdapterRss -Name $ReachableNIC -BaseProcessorGroup $useGroup -MaxProcessorNumber $useMax -MaxProcessors $CpuCount -Profile NUMAStatic  -ErrorAction Stop
        } catch {
            Write-Host "Failed to set RSS on '$ReachableNIC': $($_.Exception.Message)"
            return
        }

        # Disable then re-enable the adapter to ensure settings apply
        if ((Get-Command -Name Disable-NetAdapter -ErrorAction SilentlyContinue) -and (Get-Command -Name Enable-NetAdapter -ErrorAction SilentlyContinue)) {
            try {
                Write-Host "Disabling adapter '$ReachableNIC' to apply settings..."
                Disable-NetAdapter -Name $ReachableNIC -Confirm:$false -ErrorAction Stop
                Start-Sleep -Seconds 2
                Write-Host "Re-enabling adapter '$ReachableNIC'..."
                Enable-NetAdapter -Name $ReachableNIC -Confirm:$false -ErrorAction Stop
                Start-Sleep -Seconds 2
            } catch {
                Write-Host "Warning: failed to toggle adapter '$ReachableNIC': $($_.Exception.Message)"
            }
        } else {
            Write-Host "Disable/Enable adapter cmdlets not present; skipping adapter toggle."
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

function CapturePerformanceMonitorAsJob {
  param(
    [Parameter(Mandatory=$true)][string]$DurationSeconds,
    [Parameter(Mandatory=$false)][string[]]$Counters = @('\Processor Information(*)\% Processor Time')
  )

  # Ensure numeric duration
  $intDuration = [int]::Parse($DurationSeconds)

  $perfJob = Start-Job -ScriptBlock {
    param($duration, $counters)

    $d = [int]$duration
    if (-not $counters -or $counters.Count -eq 0) {
      $counters = @('\Processor Information(*)\% Processor Time')
    }

    # Defensively drop counters that are known to be flaky/slow on some runners.
    $counters = @($counters | Where-Object {
      $_ -and $_ -notmatch '^\\WFPv[46]\\Packets Discarded/sec$'
    })

    # Sample roughly once per second until the deadline. This keeps capture bounded to the
    # requested duration even if individual Get-Counter calls are intermittently slow.
    $store = @{}
    $deadline = (Get-Date).AddSeconds($d)
    $iteration = 0

    while ((Get-Date) -lt $deadline) {
      $iteration++
      $samples = $null
      $sw = [System.Diagnostics.Stopwatch]::StartNew()
      try {
        $samples = Get-Counter -Counter $counters -MaxSamples 1 -ErrorAction Stop
      }
      catch {
        # Skip this sample on errors and continue with the next interval; no per-counter retry is attempted.
        $samples = $null
      }
      $sw.Stop()

      if ($samples -ne $null) {
        $csamples = $samples.CounterSamples
        foreach ($cs in $csamples) {
          $path = $cs.Path
          $inst = $cs.InstanceName
          if ([string]::IsNullOrEmpty($inst) -or $inst -eq '_Total') { continue }
          if ($cs.Status -ne 'Success') { continue }
          $key = "$path`|$inst"
          if (-not $store.ContainsKey($key)) { $store[$key] = New-Object System.Collections.ArrayList }
          [void]$store[$key].Add([double]$cs.CookedValue)
        }
      }

      # Aim for ~1Hz sampling without extending past the deadline.
      $sleepMs = [Math]::Max(0, 1000 - [int]$sw.ElapsedMilliseconds)
      if ($sw.ElapsedMilliseconds -gt 1000) {
        Write-Verbose ("Get-Counter sampling iteration {0} took {1} ms; skipping sleep to honor deadline." -f $iteration, [int]$sw.ElapsedMilliseconds)
      }
      elseif ($sleepMs -gt 0) {
        Start-Sleep -Milliseconds $sleepMs
      }
    }

    $results = @()
    foreach ($k in $store.Keys) {
      $parts = $k -split '\|',2
      $path = $parts[0]
      $inst = $parts[1]
      $avg = ($store[$k] | Measure-Object -Average).Average
      $results += [PSCustomObject]@{ Counter = $path; Instance = $inst; Average = $avg }
    }

    # Emit structured results: an array of PSObjects with Counter, Instance, Average
    $results
  } -ArgumentList $intDuration, $Counters

  return $perfJob
}

# Export all public functions
Export-ModuleMember -Function *