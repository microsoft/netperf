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

    $counter = '\Processor(*)\% Processor Time'
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
      # Sort by processor name to have consistent ordering (e.g., _Total last or first)
      $sorted = $results | Sort-Object @{Expression={$_.Processor -replace '^CPU',''}},Processor
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

    try {
      # Collect all requested counters in one Get-Counter call if possible
      $samples = Get-Counter -Counter $counters -SampleInterval 1 -MaxSamples $d -ErrorAction Stop

      # Group by counter path and instance name, compute per-instance averages
      # CounterSamples contain Path, InstanceName, CounterName, CookedValue
      $groupedByCounter = $samples.CounterSamples | Group-Object -Property Path

      $results = @()
      foreach ($counterGroup in $groupedByCounter) {
        $path = $counterGroup.Name
        $innerGroups = $counterGroup.Group | Group-Object -Property InstanceName
        foreach ($inst in $innerGroups) {
          $instName = $inst.Name
          if ([string]::IsNullOrEmpty($instName) -or $instName -eq '_Total') { continue }
          $vals = $inst.Group | ForEach-Object { [double]$_.CookedValue }
          $avg = ($vals | Measure-Object -Average).Average
          $results += [PSCustomObject]@{ Counter = $path; Instance = $instName; Average = $avg }
        }
      }

      # Emit structured results: an array of PSObjects with Counter, Instance, Average
      $results
    }
    catch {
      Write-Output (@([PSCustomObject]@{ Counter = 'error'; Instance = ''; Average = 0; ErrorMessage = $_.Exception.Message }))
    }
  } -ArgumentList $intDuration, $Counters

  return $perfJob
}