param(
  [switch]$CpuProfile,
  [string]$PeerName,
  [string]$SenderOptions,
  [string]$ReceiverOptions,
  [string]$TimeoutInMilliseconds = '300000'
)

Set-StrictMode -Version Latest

# Write out the parameters for logging
Write-Host "Parameters:"
Write-Host "  CpuProfile: $CpuProfile"
Write-Host "  PeerName: $PeerName"
Write-Host "  SenderOptions: $SenderOptions"
Write-Host "  ReceiverOptions: $ReceiverOptions"
Write-Host "  TimeoutInMilliseconds: $TimeoutInMilliseconds"


# Append TimeLimit to sender and receiver options if not already present
if ($SenderOptions -notmatch '-TimeLimit:') {
  $SenderOptions += " -TimeLimit:$TimeoutInMilliseconds"
}

if ($ReceiverOptions -notmatch '-TimeLimit:') {
  $ReceiverOptions += " -TimeLimit:$TimeoutInMilliseconds"
}

# Append error file name options if not already present
if ($SenderOptions -notmatch '-ErrorFileName:') {
  $SenderOptions += " -ErrorFileName:ctsTraffic_Errors_Send.log"
}

if ($SenderOptions -notmatch '-statusfilename:') {
  $SenderOptions += " -statusfilename:ctsTrafficStatus_Send.csv"
}

if ($SenderOptions -notmatch '-connectionfilename:') {
  $SenderOptions += " -connectionfilename:ctsTrafficConnections_Send.log"
}

if ($ReceiverOptions -notmatch '-ErrorFileName:') {
  $ReceiverOptions += " -ErrorFileName:ctsTraffic_Errors_Recv.log"
}

if ($ReceiverOptions -notmatch '-statusfilename:') {
  $ReceiverOptions += " -statusfilename:ctsTrafficStatus_Send.csv"
}

if ($ReceiverOptions -notmatch '-connectionfilename:') {
  $ReceiverOptions += " -connectionfilename:ctsTrafficConnections_Send.log"
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

# Ensure an args array contains a '-target:<name>' entry; replace if present, append if missing
function Set-TargetArg {
  param(
    [Parameter(Mandatory = $true)] $ArgsArray,
    [Parameter(Mandatory = $true)] [string] $TargetName
  )
  if ($null -eq $ArgsArray) { $ArgsArray = @() }
  $found = $false
  for ($i = 0; $i -lt $ArgsArray.Count; $i++) {
    if ($ArgsArray[$i] -match '^-target:' ) {
      $ArgsArray[$i] = "-target:$TargetName"
      $found = $true
      break
    }
  }
  if (-not $found) { $ArgsArray += "-target:$TargetName" }
  return $ArgsArray
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

# WPR CPU profiling helpers
$script:WprProfiles = @{}

function Start-WprCpuProfile {
  param([Parameter(Mandatory=$true)][string]$Which)

  if (-not $CpuProfile) { return }

  if (-not $Workspace) { $Workspace = $env:GITHUB_WORKSPACE }
  $etlDir = Join-Path $Workspace 'ETL'
  if (-not (Test-Path $etlDir)) { New-Item -ItemType Directory -Path $etlDir | Out-Null }

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
      & wpr -start CPU -filemode | Out-Null
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
function Invoke-CtsInSession {
  param($Session, $RemoteDir, $Options, $StartDelay)

  $Job = Invoke-Command -Session $Session -ScriptBlock {
    param($RemoteDir, $Options)

    Set-Location $RemoteDir\cts-traffic

    $CtsTraffic = Join-Path $RemoteDir 'cts-traffic\ctsTraffic.exe'
    Write-Host "[Remote] Running: $CtsTraffic"
    if ($Options -is [System.Array]) {
      Write-Host "[Remote] Arguments (array):"
      foreach ($arg in $Options) { Write-Host "  $arg" }
    }
    else {
      Write-Host "[Remote] Arguments (string):"
      Write-Host "  $Options"
    }
    
    # If StartDelay is set, wait 10 seconds before starting.
    if ($using:StartDelay) {
      Write-Host "[Remote] StartDelay is set; waiting 10 seconds before starting ctsTraffic.exe..."
      Start-Sleep -Seconds 10
    }

    # PowerShell 7 supports positional splatting for arrays
    if ($Options -is [System.Array]) {
      & $CtsTraffic @Options
    }
    else {
      & $CtsTraffic $Options
    }

    # Convert non-zero exit to terminating error so the job records it
    if ($LASTEXITCODE -ne 0) {
      throw "Remote ctsTraffic.exe exited with code $LASTEXITCODE"
    }
  } -ArgumentList $RemoteDir, $Options -AsJob -ErrorAction Stop

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

function Copy-CtsTrafficToRemote {
  param([Parameter(Mandatory=$true)]$Session)
  # Ensure the remote base directory and the 'cts-traffic' subdirectory both exist,
  # then copy the *contents* of the local directory into the remote folder.
  Invoke-Command -Session $Session -ScriptBlock {
    param($base, $sub)
    if (-not (Test-Path $base)) { New-Item -ItemType Directory -Path $base | Out-Null }
    $full = Join-Path $base $sub
    if (-not (Test-Path $full)) { New-Item -ItemType Directory -Path $full | Out-Null }
  } -ArgumentList $script:RemoteDir, 'cts-traffic' -ErrorAction Stop

  $localPath = (Resolve-Path .).Path
  Copy-Item -ToSession $Session -Path (Join-Path $localPath '*') -Destination "$script:RemoteDir\cts-traffic" -Recurse -Force
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
  $serverArgs = $serverArgs | ForEach-Object { if ([string]::IsNullOrEmpty($_)) { $_ } else { if ($_ -like '-*') { $_ } else { '-' + $_ } } }
  Write-Host "[Local->Remote] Invoking remote job with arguments:"
  if ($serverArgs -is [System.Array]) { foreach ($arg in $serverArgs) { Write-Host "  $arg" } } else { Write-Host "  $serverArgs" }
  $Job = Invoke-CtsInSession -Session $Session -RemoteDir $script:RemoteDir -Options $serverArgs

  $clientArgs = Convert-ArgStringToArray $SenderOptions
  $clientArgs = Set-TargetArg -ArgsArray $clientArgs -TargetName $PeerName
  $clientArgs = $clientArgs | ForEach-Object { if ([string]::IsNullOrEmpty($_)) { $_ } else { if ($_ -like '-*') { $_ } else { '-' + $_ } } }

  # Delay 10 seconds to allow remote server to start before client connects
  Write-Host "[Local] Waiting 10 seconds before starting send test to allow remote receiver to initialize..."
  Start-Sleep -Seconds 10

  Write-Host "[Local] Running: .\ctsTraffic.exe"
  Write-Host "[Local] Arguments:"
  foreach ($a in $clientArgs) { Write-Host "  $a" }
  Start-WprCpuProfile -Which 'send'
  & .\ctsTraffic.exe @clientArgs
  $script:localExit = $LASTEXITCODE
  Stop-WprCpuProfile -Which 'send'

  Receive-JobOrThrow -Job $Job

  # After send test: rename local send files and fetch remote recv files
  Rename-LocalIfExists -Path 'ctsTraffic_Errors_Send.log' -NewName 'ctsTraffic_Errors_Send_Local.log'
  Rename-LocalIfExists -Path 'ctsTrafficStatus_Send.csv' -NewName 'ctsTrafficStatus_Send_Local.csv'
  Rename-LocalIfExists -Path 'ctsTrafficConnections_Send.log' -NewName 'ctsTrafficConnections_Send_Local.log'

  $fetched = Fetch-RemoteFile -Session $Session -RemotePath "$script:RemoteDir\cts-traffic\ctsTraffic_Errors_Recv.log" -LocalDestination 'ctsTraffic_Errors_Recv_Remote.log'
  if (-not $fetched) {
    Write-Host "Warning: failed to fetch remote 'ctsTraffic_Errors_Recv.log'"
  } else { Write-Host "[Run-SendTest] fetched 'ctsTraffic_Errors_Recv.log' -> 'ctsTraffic_Errors_Recv_Remote.log'" }

  $fetched = Fetch-RemoteFile -Session $Session -RemotePath "$script:RemoteDir\cts-traffic\ctsTrafficStatus_Recv.csv" -LocalDestination 'ctsTrafficStatus_Recv_Remote.csv'
  if (-not $fetched) {
    Write-Host "Warning: failed to fetch remote 'ctsTrafficStatus_Recv.csv'"
  } else { Write-Host "[Run-SendTest] fetched 'ctsTrafficStatus_Recv.csv' -> 'ctsTrafficStatus_Recv_Remote.csv'" }

  $fetched = Fetch-RemoteFile -Session $Session -RemotePath "$script:RemoteDir\cts-traffic\ctsTrafficConnections_Recv.csv" -LocalDestination 'ctsTrafficConnections_Recv_Remote.csv'
  if (-not $fetched) {
    Write-Host "Warning: failed to fetch remote 'ctsTrafficConnections_Recv.csv'"
  } else { Write-Host "[Run-SendTest] fetched 'ctsTrafficConnections_Recv.csv' -> 'ctsTrafficConnections_Recv_Remote.csv'" }
}

function Run-RecvTest {
  param(
    [Parameter(Mandatory=$true)][string]$PeerName,
    [Parameter(Mandatory=$true)]$Session,
    [Parameter(Mandatory=$true)][string]$SenderOptions,
    [Parameter(Mandatory=$true)][string]$ReceiverOptions
  )

  $serverArgs = Convert-ArgStringToArray $SenderOptions
  $serverArgs = Set-TargetArg -ArgsArray $serverArgs -TargetName $PeerName
  $serverArgs = $serverArgs | ForEach-Object { if ([string]::IsNullOrEmpty($_)) { $_ } else { if ($_ -like '-*') { $_ } else { '-' + $_ } } }
  Write-Host "[Local->Remote] Invoking remote job with arguments:"
  if ($serverArgs -is [System.Array]) { foreach ($arg in $serverArgs) { Write-Host "  $arg" } } else { Write-Host "  $serverArgs" }
  $Job = Invoke-CtsInSession -Session $Session -RemoteDir $script:RemoteDir -Options $serverArgs -StartDelay $true

  $clientArgs = Convert-ArgStringToArray $ReceiverOptions
  $clientArgs = $clientArgs | ForEach-Object { if ([string]::IsNullOrEmpty($_)) { $_ } else { if ($_ -like '-*') { $_ } else { '-' + $_ } } }

  Write-Host "[Local] Running: .\ctsTraffic.exe"
  Write-Host "[Local] Arguments:"
  foreach ($a in $clientArgs) { Write-Host "  $a" }
  Start-WprCpuProfile -Which 'recv'
  & .\ctsTraffic.exe @clientArgs
  $script:localExit = $LASTEXITCODE
  Stop-WprCpuProfile -Which 'recv'

  Receive-JobOrThrow -Job $Job

  # After recv test: rename local recv files and fetch remote send files
  Rename-LocalIfExists -Path 'ctsTraffic_Errors_Recv.log' -NewName 'ctsTraffic_Errors_Recv_Local.log'
  Rename-LocalIfExists -Path 'ctsTrafficStatus_Recv.csv' -NewName 'ctsTrafficStatus_Recv_Local.csv'
  Rename-LocalIfExists -Path 'ctsTrafficConnections_Recv.csv' -NewName 'ctsTrafficConnections_Recv_Local.csv'

  Write-Host "Fetching remote send test files..."
  $fetched = Fetch-RemoteFile -Session $Session -RemotePath "$script:RemoteDir\cts-traffic\ctsTraffic_Errors_Send.log" -LocalDestination 'ctsTraffic_Errors_Send_Remote.log'
  if (-not $fetched) {
    Write-Host "Warning: failed to fetch remote 'ctsTraffic_Errors_Send.log'"
  } else { Write-Host "[Run-RecvTest] fetched 'ctsTraffic_Errors_Send.log' -> 'ctsTraffic_Errors_Send_Remote.log'" }

  $fetched = Fetch-RemoteFile -Session $Session -RemotePath "$script:RemoteDir\cts-traffic\ctsTrafficStatus_Send.csv" -LocalDestination 'ctsTrafficStatus_Send_Remote.csv'
  if (-not $fetched) {
    Write-Host "Warning: failed to fetch remote 'ctsTrafficStatus_Send.csv'"
  } else { Write-Host "[Run-RecvTest] fetched 'ctsTrafficStatus_Send.csv' -> 'ctsTrafficStatus_Send_Remote.csv'" }

  $fetched = Fetch-RemoteFile -Session $Session -RemotePath "$script:RemoteDir\cts-traffic\ctsTrafficConnections_Send.log" -LocalDestination 'ctsTrafficConnections_Send_Remote.log'
  if (-not $fetched) {
    Write-Host "Warning: failed to fetch remote 'ctsTrafficConnections_Send.log'"
  } else { Write-Host "[Run-RecvTest] fetched 'ctsTrafficConnections_Send.log' -> 'ctsTrafficConnections_Send_Remote.log'" }
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
$Workspace = $env:GITHUB_WORKSPACE
Write-Host "Workspace: $Workspace"

try {
  if (-not $Workspace) { throw 'GITHUB_WORKSPACE is not set' }
  Set-Location (Join-Path $Workspace 'cts-traffic')

  # Create remote session
  $Session = Create-Session -PeerName $PeerName -RemotePSConfiguration 'PowerShell.7'

  # Save and disable firewalls
  Save-And-Disable-Firewalls -Session $Session

  # Copy cts-traffic to remote
  Copy-CtsTrafficToRemote -Session $Session

  # Run tests
  Run-SendTest -PeerName $PeerName -Session $Session -SenderOptions $SenderOptions -ReceiverOptions $ReceiverOptions
  Run-RecvTest -PeerName $PeerName -Session $Session -SenderOptions $SenderOptions -ReceiverOptions $ReceiverOptions

  Write-Host "cts-traffic tests completed successfully."
}
catch {
  # $_ is an ErrorRecord; print everything useful
  Write-Host "cts-traffic tests failed."
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
