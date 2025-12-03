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
