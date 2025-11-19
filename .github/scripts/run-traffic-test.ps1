param(
  [switch]$Profile,
  [string]$PeerName,
  [string]$SenderOptions,
  [string]$ReceiverOptions
)

Set-StrictMode -Version Latest

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

# Settings
$Duration = 60000
$CpuProfile = $false
if ($Profile) { $CpuProfile = $true }

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
  & .\ctsTraffic.exe @clientArgs
  if ($LASTEXITCODE -ne 0) { throw "Local ctsTraffic.exe (Send) exited with code $LASTEXITCODE" }

  Receive-JobOrThrow -Job $Job

  #
  # === Recv tests: remote sender, local receiver ===
  #
  $serverArgs = Parse-Args $SenderOptions
  # When the remote is the sender, ensure it targets the local machine (receiver)
  $serverArgs = Ensure-TargetArg -ArgsArray $serverArgs -TargetName $env:COMPUTERNAME
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
  & .\ctsTraffic.exe @clientArgs
  if ($LASTEXITCODE -ne 0) { throw "Local ctsTraffic.exe (Recv) exited with code $LASTEXITCODE" }

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
