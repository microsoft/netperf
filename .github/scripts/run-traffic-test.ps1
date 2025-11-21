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

if ($ReceiverOptions -notmatch '-ErrorFileName:') {
  $ReceiverOptions += " -ErrorFileName:ctsTraffic_Errors_Recv.log"
}

# Make errors terminate so catch can handle them
$ErrorActionPreference = 'Stop'
$Session = $null
$exitCode = 0

# Helper to parse quoted command-line option strings into an array
function Parse-Args($s) {
  if ([string]::IsNullOrEmpty($s)) { return @() }
  # Pattern allows quoted strings with backslash-escaped characters, or unquoted tokens
  $pattern = '("((?:\\.|[^"\\])*)"|[^"\s]+)'
  $matches = [regex]::Matches($s, $pattern)
  $out = @()
  foreach ($m in $matches) {
    if ($m.Groups[2].Success) {
      # Quoted token; Group 2 contains inner text with possible escapes
      $val = $m.Groups[2].Value
      # Unescape backslash-escaped sequences commonly used in CLI args
      $val = $val -replace '\\\\', '\\'
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

# Ensure an args array contains a '-target:<name>' entry; replace if present, append if missing
function Ensure-TargetArg {
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
    $repoWprp = Join-Path $Workspace 'cpu_snapshot.wprp'
    if (Test-Path $repoWprp) {
      Write-Output "Found custom WPR profile: $repoWprp. Starting WPR with that profile..."
      & wpr -start $repoWprp -filemode | Out-Null
    }
    else {
      throw "Custom WPR profile not found at $repoWprp"
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
  param($Session, $RemoteDir, $Options)

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

# =========================
# Main workflow
# =========================
$Workspace = $env:GITHUB_WORKSPACE
Write-Output "Workspace: $Workspace"

try {
  if (-not $Workspace) { throw 'GITHUB_WORKSPACE is not set' }
  Set-Location (Join-Path $Workspace 'cts-traffic')


  # Initialize localFwState variable
  $localFwState = 
  @(
    [PSCustomObject]@{ Name = "Domain"; Enabled = $true }
    [PSCustomObject]@{ Name = "Private"; Enabled = $true }
    [PSCustomObject]@{ Name = "Public"; Enabled = $true }
  )

  # Establish remote session
  $RemotePSConfiguration = 'PowerShell.7'
  $RemoteDir = 'C:\_work'
  $Username = (Get-ItemProperty 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon').DefaultUserName
  $Password = (Get-ItemProperty 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon').DefaultPassword | ConvertTo-SecureString -AsPlainText -Force
  $Creds = New-Object System.Management.Automation.PSCredential ($Username, $Password)

  try {
    Write-Output "Creating PSSession to $PeerName using configuration '$RemotePSConfiguration'..."
    $Session = New-PSSession -ComputerName $PeerName -Credential $Creds -ConfigurationName $RemotePSConfiguration -ErrorAction Stop
    Write-Output "Session created using configuration '$RemotePSConfiguration'."
  }
  catch {
    Write-Output "Failed to create session using configuration '$RemotePSConfiguration': $($_.Exception.Message)"
    Write-Output "Attempting fallback: creating session without ConfigurationName..."
    try {
      $Session = New-PSSession -ComputerName $PeerName -Credential $Creds -ErrorAction Stop
      Write-Output "Session created using default configuration."
    }
    catch {
      Write-Output "Fallback session creation failed: $($_.Exception.Message)"
      throw "Failed to create remote session to $PeerName"
    }
  }

  # Disable firewall locally and on remote (save previous states)
  Write-Output "Saving and disabling local firewall profiles..."
  $localFwState = Get-NetFirewallProfile -Profile Domain, Public, Private | Select-Object Name, Enabled
  Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled False

  Write-Output "Disabling firewall on remote machine..."
  Invoke-Command -Session $Session -ScriptBlock {
    param()
    $fw = Get-NetFirewallProfile -Profile Domain, Public, Private | Select-Object Name, Enabled
    Set-Variable -Name __SavedFirewallState -Value $fw -Scope Global -Force
    Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled False
  } -ErrorAction Stop

  # Copy cts-traffic folder to remote machine
  Copy-Item -ToSession $Session -Path (Resolve-Path .).Path -Destination "$RemoteDir\cts-traffic" -Recurse -Force

  #
  # === Send tests: remote receiver, local sender ===
  #
  $serverArgs = Parse-Args $ReceiverOptions
  # Normalize server args: ensure each explicit option starts with '-'
  $serverArgs = $serverArgs | ForEach-Object {
    if ([string]::IsNullOrEmpty($_)) { $_ } else { if ($_ -like '-*') { $_ } else { '-' + $_ } }
  }
  Write-Output "[Local->Remote] Invoking remote job with arguments:"
  if ($serverArgs -is [System.Array]) {
    foreach ($arg in $serverArgs) { Write-Output "  $arg" }
  }
  else {
    Write-Output "  $serverArgs"
  }
  $Job = Invoke-CtsInSession -Session $Session -RemoteDir $RemoteDir -Options $serverArgs

  $clientArgs = Parse-Args $SenderOptions
  # Add option to capture status file and connection file.
  $clientArgs += @('-statusfilename:ctsTrafficStatus_Send.csv', '-connectionfilename:ctsTrafficConnections_Send.csv')

  # Ensure local sender targets the remote receiver
  $clientArgs = Ensure-TargetArg -ArgsArray $clientArgs -TargetName $PeerName

  # Normalize args: ensure each explicit option starts with '-'
  $clientArgs = $clientArgs | ForEach-Object {
    if ([string]::IsNullOrEmpty($_)) { $_ } else {
      if ($_ -like '-*') { $_ } else { '-' + $_ }
    }
  }

  Write-Output "[Local] Running: .\ctsTraffic.exe"
  Write-Output "[Local] Arguments:"
  foreach ($a in $clientArgs) { Write-Output "  $a" }
  Start-WprCpuProfile -Which 'send'
  & .\ctsTraffic.exe @clientArgs
  $localExit = $LASTEXITCODE
  Stop-WprCpuProfile -Which 'send'

  Receive-JobOrThrow -Job $Job

  #
  # === Recv tests: remote sender, local receiver ===
  #
  $serverArgs = Parse-Args $SenderOptions
  # When the remote is the sender, ensure it targets the local machine (receiver)
  $serverArgs = Ensure-TargetArg -ArgsArray $serverArgs -TargetName $PeerName
  # Normalize server args: ensure each explicit option starts with '-'
  $serverArgs = $serverArgs | ForEach-Object {
    if ([string]::IsNullOrEmpty($_)) { $_ } else { if ($_ -like '-*') { $_ } else { '-' + $_ } }
  }
  Write-Output "[Local->Remote] Invoking remote job with arguments:"
  if ($serverArgs -is [System.Array]) {
    foreach ($arg in $serverArgs) { Write-Output "  $arg" }
  }
  else {
    Write-Output "  $serverArgs"
  }
  $Job = Invoke-CtsInSession -Session $Session -RemoteDir $RemoteDir -Options $serverArgs

  $clientArgs = Parse-Args $ReceiverOptions
  # Normalize recv args as well
  $clientArgs = $clientArgs | ForEach-Object {
    if ([string]::IsNullOrEmpty($_)) { $_ } else {
      if ($_ -like '-*') { $_ } else { '-' + $_ }
    }
  }

  Write-Output "[Local] Running: .\ctsTraffic.exe"
  Write-Output "[Local] Arguments:"
  foreach ($a in $clientArgs) { Write-Output "  $a" }
  $beforeNet = Get-NetworkSnapshot
  Start-WprCpuProfile -Which 'recv'
  & .\ctsTraffic.exe @clientArgs
  $localExit = $LASTEXITCODE
  Stop-WprCpuProfile -Which 'recv'
  $afterNet = Get-NetworkSnapshot
  Write-NetworkDelta -Before $beforeNet -After $afterNet -Label 'recv'
  if ($localExit -ne 0) { throw "Local ctsTraffic.exe (Recv) exited with code $localExit" }

  Receive-JobOrThrow -Job $Job

  Write-Output "cts-traffic tests completed successfully."
}
catch {
  # $_ is an ErrorRecord; print everything useful
  Write-Output "cts-traffic tests failed."
  Write-Output $_
  $exitCode = 2
}
finally {
  # Restore firewall state on remote and local if we changed it
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
  finally {
    Write-Output "Exiting with code $exitCode"
    exit $exitCode
  }
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
