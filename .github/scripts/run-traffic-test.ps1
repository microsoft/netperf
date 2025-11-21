param(
  [switch]$CpuProfile,
  [string]$PeerName,
  [string]$SenderOptions,
  [string]$ReceiverOptions,
  [string]$TimeoutInMilliseconds = '300000'
)

Set-StrictMode -Version Latest

# Write out the parameters for logging
Write-Output "Parameters:"
Write-Output "  CpuProfile: $CpuProfile"
Write-Output "  PeerName: $PeerName"
Write-Output "  SenderOptions: $SenderOptions"
Write-Output "  ReceiverOptions: $ReceiverOptions"
Write-Output "  TimeoutInMilliseconds: $TimeoutInMilliseconds"


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
  $SenderOptions += " -connectionfilename:ctsTrafficConnections_Send.csv.log"
}

if ($ReceiverOptions -notmatch '-ErrorFileName:') {
  $ReceiverOptions += " -ErrorFileName:ctsTraffic_Errors_Recv.log"
}

if ($ReceiverOptions -notmatch '-statusfilename:') {
  $ReceiverOptions += " -statusfilename:ctsTrafficStatus_Send.csv"
}

if ($ReceiverOptions -notmatch '-connectionfilename:') {
  $ReceiverOptions += " -connectionfilename:ctsTrafficConnections_Send.csv.log"
}

# Make errors terminate so catch can handle them
$ErrorActionPreference = 'Stop'
$Session = $null
$exitCode = 0

# Helper to parse quoted command-line option strings into an array
function Convert-ArgStringToArray($s) {
  if ([string]::IsNullOrEmpty($s)) { return @() }
  # Pattern allows quoted strings with backslash-escaped characters, or unquoted tokens
  $pattern = '("((?:\.|[^"\])*)"|[^"\s]+)'
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
      Rename-Item -Path $Path -NewName $NewName -ErrorAction Stop
    }
  }
  catch {
    Write-Output "Failed to rename $Path -> $NewName $($_.Exception.Message)"
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
      Write-Output "ERROR: $($er.Exception.Message)"
      if ($er.Exception.StackTrace) { Write-Output "StackTrace: $($er.Exception.StackTrace)" }
      if ($er.InvocationInfo) { Write-Output "Invocation: $($er.InvocationInfo.PositionMessage)" }
      Write-Output "ErrorRecord: $er"
    }
    elseif ($er -is [System.Exception]) {
      Write-Output "EXCEPTION: $($er.Message)"
      if ($er.StackTrace) { Write-Output "StackTrace: $($er.StackTrace)" }
    }
    else {
      Write-Output $er
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

  Write-Output "Starting WPR CPU profiling -> $outFile"
  try {
    # Check if WPR is already running to avoid the "profiles are already running" error
    $status = $null
    try {
      $status = & wpr -status 2>&1
    } catch {
      $status = $_.ToString()
    }

    if ($status -and $status -match 'profile(s)?\s+are\s+already\s+running|Profiles are already running|The profiles are already running') {
      Write-Output "WPR already running. Cancelling any existing profiles so we can start a fresh one..."
      try {
        & wpr -cancel 2>&1 | Out-Null
        Start-Sleep -Seconds 1
      }
      catch {
        Write-Output "Failed to cancel existing WPR session: $($_.Exception.Message). Proceeding to start a new profile anyway."
      }
    }

    try {
      & wpr -start CPU -filemode | Out-Null
    }
    catch {
      Write-Output "wpr -start with custom profile failed: $($_.Exception.Message). Falling back to built-in CPU profile."
      try { & wpr -start CPU -filemode | Out-Null } catch { Write-Output "Fallback CPU start also failed: $($_.Exception.Message)" }
    }
    $script:WprProfiles[$Which] = $outFile
  }
  catch {
    Write-Output "Failed to start WPR: $($_.Exception.Message)"
  }
}

function Stop-WprCpuProfile {
  param([Parameter(Mandatory=$true)][string]$Which)

  if (-not $CpuProfile) { return }

  if (-not $script:WprProfiles.ContainsKey($Which)) {
    Write-Output "No WPR profile active for '$Which'"
    return
  }

  $outFile = $script:WprProfiles[$Which]
  Write-Output "Stopping WPR CPU profiling, saving to $outFile"
  try {
    # Attempt to stop WPR and save to the given file. If no profile is running, log and continue.
    try {
      & wpr -stop $outFile | Out-Null
    }
    catch {
      Write-Output "wpr -stop failed: $($_.Exception.Message). Attempting to query status..."
      try {
        $s = & wpr -status 2>&1
        Write-Output "WPR status: $s"
      } catch { }
    }
    $script:WprProfiles.Remove($Which) | Out-Null
  }
  catch {
    Write-Output "Failed to stop WPR: $($_.Exception.Message)"
  }
}


# =========================
# Remote job helpers
# =========================
function Invoke-CtsInSession {
  param($Session, $RemoteDir, $Options, $StartDelay)

  $Job = Invoke-Command -Session $Session -ScriptBlock {
    param($RemoteDir, $Options)

    $CtsTraffic = Join-Path $RemoteDir 'cts-traffic\ctsTraffic.exe'
    Write-Output "[Remote] Running: $CtsTraffic"
    if ($Options -is [System.Array]) {
      Write-Output "[Remote] Arguments (array):"
      foreach ($arg in $Options) { Write-Output "  $arg" }
    }
    else {
      Write-Output "[Remote] Arguments (string):"
      Write-Output "  $Options"
    }
    
    # If StartDelay is set, wait 5 seconds before starting.
    if ($using:StartDelay) {
      Write-Output "[Remote] StartDelay is set; waiting 5 seconds before starting ctsTraffic.exe..."
      Start-Sleep -Seconds 5
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
    Write-Output "Creating PSSession to $PeerName using configuration '$RemotePSConfiguration'..."
    $s = New-PSSession -ComputerName $PeerName -Credential $Creds -ConfigurationName $RemotePSConfiguration -ErrorAction Stop
    Write-Output "Session created using configuration '$RemotePSConfiguration'."
  }
  catch {
    Write-Output "Failed to create session using configuration '$RemotePSConfiguration': $($_.Exception.Message)"
    Write-Output "Attempting fallback: creating session without ConfigurationName..."
    try {
      $s = New-PSSession -ComputerName $PeerName -Credential $Creds -ErrorAction Stop
      Write-Output "Session created using default configuration."
    }
    catch {
      Write-Output "Fallback session creation failed: $($_.Exception.Message)"
      throw "Failed to create remote session to $PeerName"
    }
  }

  $script:Session = $s
  return $s
}

function Save-And-Disable-Firewalls {
  param([Parameter(Mandatory=$true)]$Session)

  Write-Output "Saving and disabling local firewall profiles..."
  $script:localFwState = Get-NetFirewallProfile -Profile Domain, Public, Private | Select-Object Name, Enabled
  Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled False

  Write-Output "Disabling firewall on remote machine..."
  Invoke-Command -Session $Session -ScriptBlock {
    param()
    $fw = Get-NetFirewallProfile -Profile Domain, Public, Private | Select-Object Name, Enabled
    Set-Variable -Name __SavedFirewallState -Value $fw -Scope Global -Force
    Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled False
  } -ErrorAction Stop
}

function Copy-CtsTrafficToRemote {
  param([Parameter(Mandatory=$true)]$Session)
  Copy-Item -ToSession $Session -Path (Resolve-Path .).Path -Destination "$script:RemoteDir\cts-traffic" -Recurse -Force
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
  Write-Output "[Local->Remote] Invoking remote job with arguments:"
  if ($serverArgs -is [System.Array]) { foreach ($arg in $serverArgs) { Write-Output "  $arg" } } else { Write-Output "  $serverArgs" }
  $Job = Invoke-CtsInSession -Session $Session -RemoteDir $script:RemoteDir -Options $serverArgs

  $clientArgs = Convert-ArgStringToArray $SenderOptions
  $clientArgs = Set-TargetArg -ArgsArray $clientArgs -TargetName $PeerName
  $clientArgs = $clientArgs | ForEach-Object { if ([string]::IsNullOrEmpty($_)) { $_ } else { if ($_ -like '-*') { $_ } else { '-' + $_ } } }

  Write-Output "[Local] Running: .\ctsTraffic.exe"
  Write-Output "[Local] Arguments:"
  foreach ($a in $clientArgs) { Write-Output "  $a" }
  Start-WprCpuProfile -Which 'send'
  & .\ctsTraffic.exe @clientArgs
  $script:localExit = $LASTEXITCODE
  Stop-WprCpuProfile -Which 'send'

  Receive-JobOrThrow -Job $Job

  # After send test: rename local send files and fetch remote recv files
  Rename-LocalIfExists -Path 'ctsTraffic_Errors_Send.log' -NewName 'ctsTraffic_Errors_Send_Local.log'
  Rename-LocalIfExists -Path 'ctsTrafficStatus_Send.csv' -NewName 'ctsTrafficStatus_Send_Local.csv'
  Rename-LocalIfExists -Path 'ctsTrafficConnections_Send.csv' -NewName 'ctsTrafficConnections_Send_Local.csv'

  Copy-Item -FromSession $Session -Path "$script:RemoteDir\cts-traffic\ctsTraffic_Errors_Recv.log" -Destination 'ctsTraffic_Errors_Recv_Remote.log' -ErrorAction SilentlyContinue
  Copy-Item -FromSession $Session -Path "$script:RemoteDir\cts-traffic\ctsTrafficStatus_Recv.csv" -Destination 'ctsTrafficStatus_Recv_Remote.csv' -ErrorAction SilentlyContinue
  Copy-Item -FromSession $Session -Path "$script:RemoteDir\cts-traffic\ctsTrafficConnections_Recv.csv" -Destination 'ctsTrafficConnections_Recv_Remote.csv' -ErrorAction SilentlyContinue
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
  Write-Output "[Local->Remote] Invoking remote job with arguments:"
  if ($serverArgs -is [System.Array]) { foreach ($arg in $serverArgs) { Write-Output "  $arg" } } else { Write-Output "  $serverArgs" }
  $Job = Invoke-CtsInSession -Session $Session -RemoteDir $script:RemoteDir -Options $serverArgs

  $clientArgs = Convert-ArgStringToArray $ReceiverOptions
  $clientArgs = $clientArgs | ForEach-Object { if ([string]::IsNullOrEmpty($_)) { $_ } else { if ($_ -like '-*') { $_ } else { '-' + $_ } } }

  Write-Output "[Local] Running: .\ctsTraffic.exe"
  Write-Output "[Local] Arguments:"
  foreach ($a in $clientArgs) { Write-Output "  $a" }
  Start-WprCpuProfile -Which 'recv'
  & .\ctsTraffic.exe @clientArgs
  $script:localExit = $LASTEXITCODE
  Stop-WprCpuProfile -Which 'recv'

  Receive-JobOrThrow -Job $Job

  # After recv test: rename local recv files and fetch remote send files
  Rename-LocalIfExists -Path 'ctsTraffic_Errors_Recv.log' -NewName 'ctsTraffic_Errors_Recv_Local.log'
  Rename-LocalIfExists -Path 'ctsTrafficStatus_Recv.csv' -NewName 'ctsTrafficStatus_Recv_Local.csv'
  Rename-LocalIfExists -Path 'ctsTrafficConnections_Recv.csv' -NewName 'ctsTrafficConnections_Recv_Local.csv'

  Copy-Item -FromSession $Session -Path "$script:RemoteDir\cts-traffic\ctsTraffic_Errors_Send.log" -Destination 'ctsTraffic_Errors_Send_Remote.log' -ErrorAction SilentlyContinue
  Copy-Item -FromSession $Session -Path "$script:RemoteDir\cts-traffic\ctsTrafficStatus_Send.csv" -Destination 'ctsTrafficStatus_Send_Remote.csv' -ErrorAction SilentlyContinue
  Copy-Item -FromSession $Session -Path "$script:RemoteDir\cts-traffic\ctsTrafficConnections_Send.csv" -Destination 'ctsTrafficConnections_Send_Remote.csv' -ErrorAction SilentlyContinue
}

function Restore-FirewallAndCleanup {
  param([object]$Session)

  try {
    if ($null -ne $Session) {
      try {
        Write-Output "Restoring firewall state on remote machine..."
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

    Write-Output "Restoring local firewall state..."
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
Write-Output "Workspace: $Workspace"

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

  Write-Output "cts-traffic tests completed successfully."
}
catch {
  # $_ is an ErrorRecord; print everything useful
  Write-Output "cts-traffic tests failed."
  Write-Output $_
  $exitCode = 2
}
finally {
    # Use refactored cleanup function
    Restore-FirewallAndCleanup -Session $Session
    Write-Output "Exiting with code $exitCode"
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
