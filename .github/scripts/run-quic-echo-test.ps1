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

  if (Test-Path -LiteralPath $StartDir) {
    $item = Get-Item -LiteralPath $StartDir
    if ($item.PSIsContainer) {
      $dir = $item.FullName
    }
    else {
      $dir = $item.DirectoryName
    }
  }
  else {
    $dir = $StartDir
  }
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
$twoLevelsUp = Join-Path $scriptDir '..\..'
$moduleCandidates = @(
  (Join-Path $scriptDir $moduleName),
  (Join-Path $scriptDir '..' $moduleName),
  (Join-Path $twoLevelsUp $moduleName)
)

if ($env:GITHUB_WORKSPACE) {
  $githubScriptsDir = Join-Path $env:GITHUB_WORKSPACE '.github\scripts'
  $moduleCandidates += (Join-Path $githubScriptsDir $moduleName)
}

$repoRoot = Find-RepoRoot -StartDir $scriptDir
if ($repoRoot) {
  $repoScriptsDir = Join-Path $repoRoot '.github\scripts'
  $moduleCandidates += (Join-Path $repoScriptsDir $moduleName)
}

$modulePath = $moduleCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $modulePath) {
  $moduleCandidatesString = ($moduleCandidates | ForEach-Object { "  $_" }) -join [Environment]::NewLine
  Write-Error -ErrorAction Stop -Message ("Could not find required module '{0}'. Tried:{1}{2}" -f $moduleName, [Environment]::NewLine, $moduleCandidatesString)
}

Import-Module $modulePath -Force

# Write out the parameters for logging
Write-Host "Parameters:"
Write-Host "  CpuProfile: $CpuProfile"
Write-Host "  PeerName: $PeerName"
Write-Host "  SenderOptions: $SenderOptions"
Write-Host "  ReceiverOptions: $ReceiverOptions"
Write-Host "  Duration: $Duration"

# Ensure --backend msquic is present in sender (client) options
if ($SenderOptions -notmatch '--backend') {
  $SenderOptions += " --backend msquic"
}

# Ensure --server is in the sender/client options
if ($SenderOptions -notmatch '--server') {
  $SenderOptions += " --server $PeerName"
}

# Ensure --insecure is in the sender/client options for benchmark convenience
if ($SenderOptions -notmatch '--insecure') {
  $SenderOptions += " --insecure"
}

# Ensure --backend msquic is present in receiver (server) options
if ($ReceiverOptions -notmatch '--backend') {
  $ReceiverOptions += " --backend msquic"
}

# Validate and parse duration up-front
$durationInt = 60
if ($Duration) {
  if (-not [int]::TryParse($Duration, [ref]$durationInt) -or $durationInt -le 0) {
    throw "Invalid duration '$Duration': must be a positive integer (seconds)"
  }
}

# Compute timeout with buffer for startup/cleanup overhead
$script:processTimeoutMs = ($durationInt + 60) * 1000
$script:jobTimeoutSec    = $durationInt + 120

# Add duration option if not already present
if ($SenderOptions -notmatch '--duration') {
  $SenderOptions += " --duration $durationInt"
}
if ($ReceiverOptions -notmatch '--duration') {
  $ReceiverOptions += " --duration $durationInt"
}

$ErrorActionPreference = 'Stop'
$Session = $null
$exitCode = 0
$script:serverProc = $null
$script:cpuMonitorJob = $null
$script:perfCounterJob = $null
$localFwState = $null
$localCertThumbprint = $null
$remoteCertThumbprint = $null
$script:localCertStoreLocation = 'CurrentUser'
$script:remoteCertStoreLocation = 'CurrentUser'
$script:driverCodeSigningThumbprint = $null
$script:driverCodeSigningCerPath = $null

function Write-Phase {
  param([Parameter(Mandatory=$true)][string]$Message)
  Write-Host "[$(Get-Date -Format o)] $Message"
}

function Test-IsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ReceiverBackend {
  param([Parameter(Mandatory=$true)][string]$Options)

  $tokens = Normalize-Args -Tokens (Convert-ArgStringToArray $Options)
  for ($i = 0; $i -lt $tokens.Count; $i++) {
    if ($tokens[$i] -eq '--backend' -and ($i + 1) -lt $tokens.Count) {
      return $tokens[$i + 1]
    }
  }

  return 'msquic'
}

function Get-QuicEchoKmDriverPath {
  $toolRoot = Split-Path -Parent $scriptDir
  $driverPath = Join-Path $toolRoot 'km\winquicecho_km.sys'
  if (-not (Test-Path -LiteralPath $driverPath)) {
    throw "Required kernel driver not found: $driverPath"
  }

  return $driverPath
}

function Test-LocalTestSigningEnabled {
  $output = (& bcdedit /enum '{current}' 2>$null | Out-String)
  return $output -match '(?im)^\s*testsigning\s+Yes\s*$'
}

function Test-RemoteTestSigningEnabled {
  param([Parameter(Mandatory=$true)]$Session)

  return Invoke-Command -Session $Session -ScriptBlock {
    $output = (& bcdedit /enum '{current}' 2>$null | Out-String)
    return ($output -match '(?im)^\s*testsigning\s+Yes\s*$')
  } -ErrorAction Stop
}

function Get-SignToolPath {
  $signtool = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin" -Recurse -Filter 'signtool.exe' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\x64\\signtool\.exe$' } |
    Sort-Object FullName -Descending |
    Select-Object -First 1

  if ($signtool) {
    return $signtool.FullName
  }

  return $null
}

function Prepare-WinQuicEchoKmDriver {
  param(
    [Parameter(Mandatory=$true)]$Session,
    [Parameter(Mandatory=$true)][string]$DriverSourcePath,
    [Parameter(Mandatory=$true)][string]$RemoteDir
  )

  if (-not (Test-LocalTestSigningEnabled)) {
    throw 'Local machine does not have test signing enabled. Enable it with "bcdedit /set testsigning on" and reboot.'
  }
  if (-not (Test-RemoteTestSigningEnabled -Session $Session)) {
    throw 'Remote machine does not have test signing enabled. Enable it with "bcdedit /set testsigning on" and reboot.'
  }

  $signtoolPath = Get-SignToolPath

  $codeCert = New-SelfSignedCertificate `
    -Type CodeSigningCert `
    -Subject 'CN=WinQuicEcho Netperf Test' `
    -CertStoreLocation 'Cert:\LocalMachine\My' `
    -NotAfter (Get-Date).AddHours(2)
  $script:driverCodeSigningThumbprint = $codeCert.Thumbprint
  $script:driverCodeSigningCerPath = Join-Path $env:TEMP "winquicecho_netperf_$($codeCert.Thumbprint).cer"

  Export-Certificate -Cert $codeCert -FilePath $script:driverCodeSigningCerPath -Force | Out-Null
  certutil -addstore Root $script:driverCodeSigningCerPath | Out-Null
  certutil -addstore TrustedPublisher $script:driverCodeSigningCerPath | Out-Null

  Write-Phase "Signing WinQuicEcho kernel driver with temporary test certificate $script:driverCodeSigningThumbprint"
  if ($signtoolPath) {
    & $signtoolPath sign /v /fd sha256 /sm /s My /sha1 $script:driverCodeSigningThumbprint $DriverSourcePath
    if ($LASTEXITCODE -ne 0) {
      throw "signtool failed with exit code $LASTEXITCODE"
    }
  }
  else {
    Write-Phase 'signtool.exe not found; falling back to Set-AuthenticodeSignature'
    $signature = Set-AuthenticodeSignature -FilePath $DriverSourcePath -Certificate $codeCert -HashAlgorithm SHA256
    if ($signature.Status -ne 'Valid') {
      throw "Set-AuthenticodeSignature failed with status $($signature.Status): $($signature.StatusMessage)"
    }
  }

  $remoteCerPath = Join-Path (Join-Path $RemoteDir 'quic_echo') 'km\winquicecho_km.cer'
  Copy-Item -ToSession $Session -Path $script:driverCodeSigningCerPath -Destination $remoteCerPath -Force
  Invoke-Command -Session $Session -ArgumentList $remoteCerPath -ScriptBlock {
    param($cerPath)
    certutil -addstore Root $cerPath | Out-Null
    certutil -addstore TrustedPublisher $cerPath | Out-Null
  } -ErrorAction Stop
}

function Install-LocalWinQuicEchoKmDriver {
  param([Parameter(Mandatory=$true)][string]$DriverSourcePath)

  if (-not (Test-IsAdministrator)) {
    throw "Installing the WinQuicEcho kernel driver locally requires administrator privileges."
  }

  $serviceName = 'WinQuicEcho'
  $driverDest = Join-Path $env:SystemRoot 'System32\drivers\winquicecho_km.sys'

  $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
  if ($null -ne $svc) {
    if ($svc.Status -eq 'Running') {
      Write-Phase "Stopping existing local $serviceName service"
      & sc.exe stop $serviceName | Out-Null
      Start-Sleep -Seconds 2
    }
    Write-Phase "Deleting existing local $serviceName service"
    & sc.exe delete $serviceName | Out-Null
    Start-Sleep -Seconds 2
  }

  Write-Phase "Copying local WinQuicEcho driver to $driverDest"
  Copy-Item -LiteralPath $DriverSourcePath -Destination $driverDest -Force

  Write-Phase "Creating local $serviceName kernel service"
  & sc.exe create $serviceName type= kernel binPath= $driverDest start= demand depend= msquic | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Local sc create failed with exit code $LASTEXITCODE"
  }

  Write-Phase "Starting local $serviceName kernel service"
  & sc.exe start $serviceName
  if ($LASTEXITCODE -ne 0) {
    throw "Local sc start failed with exit code $LASTEXITCODE"
  }
}

function Install-RemoteWinQuicEchoKmDriver {
  param(
    [Parameter(Mandatory=$true)]$Session,
    [Parameter(Mandatory=$true)][string]$DriverSourcePath,
    [Parameter(Mandatory=$true)][string]$RemoteDir
  )

  $remoteKmDir = Join-Path (Join-Path $RemoteDir 'quic_echo') 'km'
  $remoteDriverSourcePath = Join-Path $remoteKmDir 'winquicecho_km.sys'

  Invoke-Command -Session $Session -ArgumentList $remoteKmDir -ScriptBlock {
    param($kmDir)
    if (-not (Test-Path -LiteralPath $kmDir)) {
      New-Item -ItemType Directory -Path $kmDir -Force | Out-Null
    }
  } -ErrorAction Stop

  Write-Phase "Copying WinQuicEcho kernel driver to remote path $remoteDriverSourcePath"
  Copy-Item -ToSession $Session -LiteralPath $DriverSourcePath -Destination $remoteDriverSourcePath -Force

  Invoke-Command -Session $Session -ArgumentList $remoteDriverSourcePath -ScriptBlock {
    param($driverSourcePath)

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
      throw "Installing the WinQuicEcho kernel driver remotely requires administrator privileges."
    }

    $serviceName = 'WinQuicEcho'
    $driverDest = Join-Path $env:SystemRoot 'System32\drivers\winquicecho_km.sys'
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($null -ne $svc) {
      if ($svc.Status -eq 'Running') {
        Write-Host "Stopping existing remote $serviceName service"
        & sc.exe stop $serviceName | Out-Null
        Start-Sleep -Seconds 2
      }
      Write-Host "Deleting existing remote $serviceName service"
      & sc.exe delete $serviceName | Out-Null
      Start-Sleep -Seconds 2
    }

    Write-Host "Copying remote WinQuicEcho driver to $driverDest"
    Copy-Item -LiteralPath $driverSourcePath -Destination $driverDest -Force

    Write-Host "Creating remote $serviceName kernel service"
    & sc.exe create $serviceName type= kernel binPath= $driverDest start= demand depend= msquic | Out-Null
    if ($LASTEXITCODE -ne 0) {
      throw "Remote sc create failed with exit code $LASTEXITCODE"
    }

    Write-Host "Starting remote $serviceName kernel service"
    & sc.exe start $serviceName
    if ($LASTEXITCODE -ne 0) {
      throw "Remote sc start failed with exit code $LASTEXITCODE"
    }
  } -ErrorAction Stop
}

function Wait-JobWithProgress {
  param(
    [Parameter(Mandatory=$true)]$Job,
    [Parameter(Mandatory=$true)][string]$Name,
    [int]$TimeoutSeconds = 15,
    [int]$MaxSeconds = 0
  )

  if ($MaxSeconds -le 0) { $MaxSeconds = $script:jobTimeoutSec }

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  while ($true) {
    if ($sw.Elapsed.TotalSeconds -ge $MaxSeconds) {
      $sw.Stop()
      Stop-Job -Job $Job -ErrorAction SilentlyContinue
      throw "TIMEOUT: $Name did not complete within ${MaxSeconds}s"
    }
    $completed = Wait-Job -Job $Job -Timeout $TimeoutSeconds
    if ($completed) { break }

    $state = $Job.JobStateInfo.State
    Write-Phase "Still waiting on $Name (JobId=$($Job.Id), State=$state, Elapsed=$([Math]::Round($sw.Elapsed.TotalSeconds, 0))s)"
  }

  $sw.Stop()
  $state = $Job.JobStateInfo.State
  Write-Phase "$Name completed (JobId=$($Job.Id), State=$state, Elapsed=$([Math]::Round($sw.Elapsed.TotalSeconds, 2))s)"
}

function New-QuicDevCert {
  <#
    .SYNOPSIS
    Creates a self-signed certificate for WinQuicEcho in the requested cert store
    and returns the thumbprint. Cleans up any stale certs from prior runs first.
  #>
  param(
    [ValidateSet('CurrentUser', 'LocalMachine')]
    [string]$StoreLocation = 'CurrentUser'
  )

  if ($StoreLocation -eq 'LocalMachine' -and -not (Test-IsAdministrator)) {
    throw "LocalMachine certificate store access requires administrator privileges."
  }

  $certStorePath = "Cert:\$StoreLocation\My"

  # Remove stale certs from interrupted prior runs
  Get-ChildItem $certStorePath | Where-Object { $_.FriendlyName -eq 'WinQuicEcho Dev Cert' } | ForEach-Object {
    Write-Host "Removing stale local dev cert: $($_.Thumbprint)"
    Remove-Item "$certStorePath\$($_.Thumbprint)" -Force -ErrorAction SilentlyContinue
  }
  $cert = New-SelfSignedCertificate `
      -DnsName "localhost" `
      -CertStoreLocation $certStorePath `
      -FriendlyName "WinQuicEcho Dev Cert" `
      -NotAfter (Get-Date).AddHours(2) `
      -KeyAlgorithm RSA `
      -KeyLength 2048 `
      -HashAlgorithm SHA256
  Write-Host "Created dev certificate in ${StoreLocation}\My: $($cert.Thumbprint)"
  return $cert.Thumbprint
}

function New-RemoteQuicDevCert {
  <#
    .SYNOPSIS
    Creates a self-signed certificate on the remote machine via PS remoting.
    Returns the thumbprint. Cleans up stale certs from prior runs first.
  #>
  param(
    [Parameter(Mandatory=$true)]$Session,
    [ValidateSet('CurrentUser', 'LocalMachine')]
    [string]$StoreLocation = 'CurrentUser'
  )
  $thumbprint = Invoke-Command -Session $Session -ArgumentList $StoreLocation -ScriptBlock {
    param($requestedStoreLocation)

    if ($requestedStoreLocation -eq 'LocalMachine') {
      $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
      $principal = [Security.Principal.WindowsPrincipal]::new($identity)
      if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Remote LocalMachine certificate store access requires administrator privileges."
      }
    }

    $certStorePath = "Cert:\$requestedStoreLocation\My"

    # Remove stale certs from interrupted prior runs
    Get-ChildItem $certStorePath | Where-Object { $_.FriendlyName -eq 'WinQuicEcho Dev Cert' } | ForEach-Object {
      Write-Host "Removing stale remote dev cert: $($_.Thumbprint)"
      Remove-Item "$certStorePath\$($_.Thumbprint)" -Force -ErrorAction SilentlyContinue
    }
    $cert = New-SelfSignedCertificate `
        -DnsName "localhost" `
        -CertStoreLocation $certStorePath `
        -FriendlyName "WinQuicEcho Dev Cert" `
        -NotAfter (Get-Date).AddHours(2) `
        -KeyAlgorithm RSA `
        -KeyLength 2048 `
        -HashAlgorithm SHA256
    return $cert.Thumbprint
  }
  Write-Host "Created remote dev certificate in ${StoreLocation}\My: $thumbprint"
  return $thumbprint
}

function Remove-QuicDevCert {
  <#
    .SYNOPSIS
    Removes WinQuicEcho dev certificates from the requested store by thumbprint.
  #>
  param(
    [string]$Thumbprint,
    [ValidateSet('CurrentUser', 'LocalMachine')]
    [string]$StoreLocation = 'CurrentUser'
  )
  if ($Thumbprint) {
    try {
      $certPath = "Cert:\$StoreLocation\My\$Thumbprint"
      if (Test-Path $certPath) {
        Remove-Item $certPath -Force
        Write-Host "Removed local dev certificate from ${StoreLocation}\My: $Thumbprint"
      }
    } catch {
      Write-Warning "Failed to remove local dev certificate: $($_.Exception.Message)"
    }
  }
}

function Remove-RemoteQuicDevCert {
  <#
    .SYNOPSIS
    Removes WinQuicEcho dev certificates from the requested remote store.
  #>
  param(
    [Parameter(Mandatory=$true)]$Session,
    [string]$Thumbprint,
    [ValidateSet('CurrentUser', 'LocalMachine')]
    [string]$StoreLocation = 'CurrentUser'
  )
  if ($Thumbprint -and $Session) {
    try {
      Invoke-Command -Session $Session -ArgumentList $Thumbprint, $StoreLocation -ScriptBlock {
        param($tp, $requestedStoreLocation)
        $certPath = "Cert:\$requestedStoreLocation\My\$tp"
        if (Test-Path $certPath) {
          Remove-Item $certPath -Force
        }
      }
      Write-Host "Removed remote dev certificate from ${StoreLocation}\My: $Thumbprint"
    } catch {
      Write-Warning "Failed to remove remote dev certificate: $($_.Exception.Message)"
    }
  }
}

function Wait-JobWithTimeout {
  <#
    .SYNOPSIS
    Waits for a job to complete within a timeout.
    Returns $true if completed, $false if timed out.
  #>
  param(
    [Parameter(Mandatory=$true)]$Job,
    [Parameter(Mandatory=$true)][string]$Name,
    [int]$TimeoutSeconds = 300
  )

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
    $completed = Wait-Job -Job $Job -Timeout 15
    if ($completed) {
      Write-Phase "$Name job completed (State=$($Job.State), Elapsed=$([Math]::Round($sw.Elapsed.TotalSeconds))s)"
      return $true
    }
    Write-Phase "Still waiting on $Name (State=$($Job.State), Elapsed=$([Math]::Round($sw.Elapsed.TotalSeconds))s)"
  }

  Write-Phase "TIMEOUT: $Name did not complete within ${TimeoutSeconds}s — stopping job"
  Stop-Job -Job $Job -ErrorAction SilentlyContinue
  return $false
}

# Safely stops a remote PS job and kills the associated native process on the remote host.
function Stop-RemoteJobAndProcess {
  param(
    [Parameter(Mandatory=$true)]$Job,
    [Parameter(Mandatory=$true)]$Session,
    [Parameter(Mandatory=$true)][string]$ProcessName
  )
  try {
    if ($Job.State -eq 'Running') {
      Stop-Job -Job $Job -ErrorAction SilentlyContinue
    }
    Invoke-Command -Session $Session -ScriptBlock {
      param($name)
      Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    } -ArgumentList $ProcessName
  } catch {
    Write-Warning "Failed to clean up remote ${ProcessName}: $_"
  }
}

function Run-SendTest {
  param(
    [Parameter(Mandatory=$true)][string]$PeerName,
    [Parameter(Mandatory=$true)]$Session,
    [Parameter(Mandatory=$true)][string]$SenderOptions,
    [Parameter(Mandatory=$true)][string]$ReceiverOptions,
    [Parameter(Mandatory=$true)][string]$RemoteCertThumbprint
  )

  # Server runs on remote — add cert-hash for the remote cert
  $serverArgs = Convert-ArgStringToArray $ReceiverOptions
  $serverArgs = Normalize-Args -Tokens $serverArgs
  $serverArgs += @('--cert-hash', $RemoteCertThumbprint, '--verbose')
  Write-Host "[Local->Remote] Invoking remote echo_server with arguments:"
  if ($serverArgs -is [System.Array]) { foreach ($arg in $serverArgs) { Write-Host "  $arg" } } else { Write-Host "  $serverArgs" }
  $Job = Invoke-ToolInSession -Session $Session -RemoteDir $script:RemoteDir -ToolDir 'quic_echo' -ToolName "echo_server" -Options $serverArgs -WaitSeconds 0

  try {
    # Give the server a moment to start listening before the client connects
    Write-Phase "Waiting 5s for remote echo_server to initialize..."
    Start-Sleep -Seconds 5
    if ($Job.State -ne 'Running') {
      $null = Receive-Job $Job -Keep -ErrorAction SilentlyContinue
      foreach ($cj in $Job.ChildJobs) {
        foreach ($line in $cj.Output) { Write-Host "[Remote stdout] $line" }
        foreach ($line in $cj.Error) { Write-Host "[Remote stderr] $line" }
      }
      throw "Remote echo_server exited during startup (State=$($Job.State))"
    }

    # Client runs locally
    $clientArgs = Convert-ArgStringToArray $SenderOptions
    $clientArgs = Normalize-Args -Tokens $clientArgs
    $clientArgs += @('--stats-file', 'quic_echo_client_stats.json', '--verbose')

    Write-Host "[Local] Running: .\echo_client.exe"
    Write-Host "[Local] Arguments:"
    foreach ($a in $clientArgs) { Write-Host "  $a" }
    Start-WprCpuProfile -Which 'send' -CpuProfile:$CpuProfile
    try {
      & .\echo_client.exe @clientArgs
      $script:localExit = $LASTEXITCODE
      Write-Phase "Local echo_client exited with code $script:localExit"
    } finally {
      Stop-WprCpuProfile -Which 'send' -CpuProfile:$CpuProfile
    }
    if ($script:localExit -ne 0) { throw "Local echo_client exited with non-zero code $script:localExit" }

    Write-Phase "Waiting for remote echo_server job to complete..."
    $serverCompleted = Wait-JobWithTimeout -Job $Job -Name 'Remote echo_server (send)' -TimeoutSeconds $script:jobTimeoutSec
    $null = Receive-Job $Job -Keep -ErrorAction SilentlyContinue
    # Drain remote output for diagnostics
    foreach ($cj in $Job.ChildJobs) {
      foreach ($line in $cj.Output) { Write-Host "[Remote stdout] $line" }
      foreach ($line in $cj.Error) { Write-Host "[Remote stderr] $line" }
    }
    if (-not $serverCompleted) {
      Write-Warning "Remote echo_server timed out (likely MsQuic cleanup hang). Client exit code: $script:localExit"
      if ($script:localExit -ne 0) {
        throw "Client failed with exit code $script:localExit AND server timed out"
      }
    } else {
      $errs = @()
      foreach ($cj in $Job.ChildJobs) {
        if ($cj.JobStateInfo.State -eq 'Failed' -and $cj.JobStateInfo.Reason) {
          $errs += $cj.JobStateInfo.Reason
        }
      }
      if ($errs.Count -gt 0) { throw "Remote echo_server errors: $($errs -join '; ')" }
    }
  } finally {
    # Always clean up the remote server job/process regardless of success or failure
    Stop-RemoteJobAndProcess -Job $Job -Session $Session -ProcessName 'echo_server'
  }
}

function Run-RecvTest {
  param(
    [Parameter(Mandatory=$true)][string]$PeerName,
    [Parameter(Mandatory=$true)]$Session,
    [Parameter(Mandatory=$true)][string]$SenderOptions,
    [Parameter(Mandatory=$true)][string]$ReceiverOptions,
    [Parameter(Mandatory=$true)][string]$LocalCertThumbprint
  )

  # Server runs locally — start first so it's listening before the client connects
  $serverArgs = Convert-ArgStringToArray $ReceiverOptions
  $serverArgs = Normalize-Args -Tokens $serverArgs
  $serverArgs += @('--cert-hash', $LocalCertThumbprint, '--verbose')

  Write-Host "[Local] Running: .\echo_server.exe (background process)"
  Write-Host "[Local] Arguments:"
  foreach ($a in $serverArgs) { Write-Host "  $a" }
  Start-WprCpuProfile -Which 'recv' -CpuProfile:$CpuProfile
  try {
    $serverExe = (Resolve-Path .\echo_server.exe).Path
    $script:serverProc = Start-Process -FilePath $serverExe -ArgumentList $serverArgs -PassThru -NoNewWindow

    # Give the server time to start listening
    Write-Phase "Waiting 5s for local echo_server to initialize..."
    Start-Sleep -Seconds 5

    # Client runs on remote
    $clientArgs = Convert-ArgStringToArray $SenderOptions
    $clientArgs = Normalize-Args -Tokens $clientArgs
    $clientArgs += @('--verbose')
    Write-Host "[Local->Remote] Invoking remote echo_client with arguments:"
    if ($clientArgs -is [System.Array]) { foreach ($arg in $clientArgs) { Write-Host "  $arg" } } else { Write-Host "  $clientArgs" }
    $Job = Invoke-ToolInSession -Session $Session -RemoteDir $script:RemoteDir -ToolDir 'quic_echo' -ToolName "echo_client" -Options $clientArgs -WaitSeconds 0

    # Wait for local server to finish (it exits after --duration)
    Write-Phase "Waiting for local echo_server process to exit..."
    $serverTimedOut = $false
    if (-not $script:serverProc.WaitForExit($script:processTimeoutMs)) {
      Write-Warning "Local echo_server did not exit within $($script:processTimeoutMs / 1000)s — killing process (PID $($script:serverProc.Id))"
      Stop-Process -Id $script:serverProc.Id -Force -ErrorAction SilentlyContinue
      $script:serverProc.WaitForExit(5000)
      $serverTimedOut = $true
    }
    # Refresh process object to ensure ExitCode is available after kill
    $script:serverProc.Refresh()
    $script:localExit = if ($serverTimedOut) { -1 } else { $script:serverProc.ExitCode }
    Write-Phase "Local echo_server exited with code $script:localExit (timedOut=$serverTimedOut)"
  } finally {
    Stop-WprCpuProfile -Which 'recv' -CpuProfile:$CpuProfile
  }

  # Wrap server-exit checks and remote job wait in try/finally to ensure the
  # remote echo_client job/process is always cleaned up, even when the local
  # server fails or times out.
  try {
    if ($serverTimedOut) { throw "Local echo_server timed out after $($script:processTimeoutMs / 1000)s" }
    if ($script:localExit -ne 0) { throw "Local echo_server exited with non-zero code $script:localExit" }

    Write-Phase "Waiting for remote echo_client job to complete..."
    $clientCompleted = Wait-JobWithTimeout -Job $Job -Name 'Remote echo_client (recv)' -TimeoutSeconds $script:jobTimeoutSec
    $null = Receive-Job $Job -Keep -ErrorAction SilentlyContinue
    foreach ($cj in $Job.ChildJobs) {
      foreach ($line in $cj.Output) { Write-Host "[Remote stdout] $line" }
      foreach ($line in $cj.Error) { Write-Host "[Remote stderr] $line" }
    }
    if (-not $clientCompleted) {
      Write-Warning "Remote echo_client timed out. Local server exit code: $script:localExit"
      if ($script:localExit -ne 0) {
        throw "Local server failed with exit code $script:localExit AND remote client timed out"
      }
    } else {
      $errs = @()
      foreach ($cj in $Job.ChildJobs) {
        if ($cj.JobStateInfo.State -eq 'Failed' -and $cj.JobStateInfo.Reason) {
          $errs += $cj.JobStateInfo.Reason
        }
      }
      if ($errs.Count -gt 0) { throw "Remote echo_client errors: $($errs -join '; ')" }
    }
  } finally {
    Stop-RemoteJobAndProcess -Job $Job -Session $Session -ProcessName 'echo_client'
  }
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

  $cwd = (Get-Location).Path
  Write-Host "[$(Get-Date -Format o)] Current working directory: $cwd"

  Get-NetAdapterRss

  Write-Host "[$(Get-Date -Format o)] Starting QUIC echo tests to peer '$PeerName' with duration $durationInt seconds..."

  # Create remote session
  $Session = Create-Session -PeerName $PeerName -RemotePSConfiguration 'PowerShell.7'

  $script:RemoteDir = 'C:\_work'
  $script:RemotePSConfiguration = 'PowerShell.7'

  # Save and disable firewalls
  Save-And-Disable-Firewalls -Session $Session

  # Copy tool to remote
  Copy-ToolDirToRemote -Session $Session -RemoteDir $script:RemoteDir -ToolDir 'quic_echo'

  $receiverBackend = Get-ReceiverBackend -Options $ReceiverOptions
  if ($receiverBackend -eq 'msquic-km') {
    $kmDriverPath = Get-QuicEchoKmDriverPath
    Write-Phase "Receiver backend is msquic-km; installing WinQuicEcho kernel driver locally and remotely"
    Prepare-WinQuicEchoKmDriver -Session $Session -DriverSourcePath $kmDriverPath -RemoteDir $script:RemoteDir
    Install-LocalWinQuicEchoKmDriver -DriverSourcePath $kmDriverPath
    Install-RemoteWinQuicEchoKmDriver -Session $Session -DriverSourcePath $kmDriverPath -RemoteDir $script:RemoteDir
  }

  # Diagnostic: verify executables and msquic.dll are present locally and remotely
  Write-Phase "Verifying local tool files..."
  @('echo_server.exe', 'echo_client.exe', 'msquic.dll') | ForEach-Object {
    $exists = Test-Path $_
    Write-Host "  $_ : $(if ($exists) { 'FOUND' } else { 'MISSING' })"
    if (-not $exists) { throw "Required file $_ not found in $(Get-Location)" }
  }
  Write-Phase "Verifying remote tool files..."
  Invoke-Command -Session $Session -ScriptBlock {
    param($dir)
    $toolDir = Join-Path $dir 'quic_echo'
    Write-Host "  Remote tool directory: $toolDir"
    Get-ChildItem $toolDir | ForEach-Object { Write-Host "    $($_.Name) ($($_.Length) bytes)" }
  } -ArgumentList $script:RemoteDir

  # Generate dev certificates on both local and remote machines
  Write-Phase "Generating dev certificates for QUIC TLS"
  if ($receiverBackend -eq 'msquic-km') {
    $script:localCertStoreLocation = 'LocalMachine'
    $script:remoteCertStoreLocation = 'LocalMachine'
  }
  Write-Phase "Receiver backend '$receiverBackend' will use local cert store '$script:localCertStoreLocation' and remote cert store '$script:remoteCertStoreLocation'"
  $localCertThumbprint = New-QuicDevCert -StoreLocation $script:localCertStoreLocation
  $remoteCertThumbprint = New-RemoteQuicDevCert -Session $Session -StoreLocation $script:remoteCertStoreLocation

  # ---- Send phase ----
  Write-Phase "Starting CPU/perf counter jobs (send phase)"
  $script:cpuMonitorJob = CaptureIndividualCpuUsagePerformanceMonitorAsJob -DurationSeconds $durationInt
  $script:perfCounterJob = CapturePerformanceMonitorAsJob -DurationSeconds $durationInt -Counters $PerformanceCounters

  Write-Phase "Starting send test"
  Run-SendTest -PeerName $PeerName -Session $Session -SenderOptions $SenderOptions -ReceiverOptions $ReceiverOptions -RemoteCertThumbprint $remoteCertThumbprint
  Write-Phase "Send test finished"

  Write-Phase "Waiting for CPU monitor job (send phase)"
  Wait-JobWithProgress -Job $script:cpuMonitorJob -Name 'CPU monitor (send)'
  $cpuUsagePerCpu = Receive-Job -Job $script:cpuMonitorJob -Wait -AutoRemoveJob
  $script:cpuMonitorJob = $null
  if ($cpuUsagePerCpu -is [System.Array]) {
    $i = 0
    foreach ($val in $cpuUsagePerCpu) {
      $i++
      Write-Host "CPU$i $([math]::Round([double]$val, 2)) %"
    }
    $overall = (($cpuUsagePerCpu | Measure-Object -Average).Average)
    Write-Host "Overall average CPU Usage: $([math]::Round($overall, 2)) %"
  }
  else {
    Write-Host "CPU1 $([math]::Round([double]$cpuUsagePerCpu, 2)) %"
  }

  Write-Phase "Waiting for perf counter job (send phase)"
  Wait-JobWithProgress -Job $script:perfCounterJob -Name 'Perf counters (send)'
  $perfResults = Receive-Job -Job $script:perfCounterJob -Wait -AutoRemoveJob
  $script:perfCounterJob = $null
  $perfJsonPath = Join-Path $cwd 'quic_echo_client_perf_counters.json'
  $perfResults | ConvertTo-Json | Out-File -FilePath $perfJsonPath -Encoding utf8 -Force
  Write-Phase "Perf counter JSON written (send phase): $perfJsonPath"

  # ---- Recv phase ----
  Write-Phase "Starting CPU/perf counter jobs (recv phase)"
  $script:cpuMonitorJob = CaptureIndividualCpuUsagePerformanceMonitorAsJob -DurationSeconds $durationInt
  $script:perfCounterJob = CapturePerformanceMonitorAsJob -DurationSeconds $durationInt -Counters $PerformanceCounters

  Write-Phase "Starting recv test"
  Run-RecvTest -PeerName $PeerName -Session $Session -SenderOptions $SenderOptions -ReceiverOptions $ReceiverOptions -LocalCertThumbprint $localCertThumbprint
  Write-Phase "Recv test finished"

  Write-Phase "Waiting for CPU monitor job (recv phase)"
  Wait-JobWithProgress -Job $script:cpuMonitorJob -Name 'CPU monitor (recv)'
  $cpuUsagePerCpu = Receive-Job -Job $script:cpuMonitorJob -Wait -AutoRemoveJob
  $script:cpuMonitorJob = $null
  if ($cpuUsagePerCpu -is [System.Array]) {
    $i = 0
    foreach ($val in $cpuUsagePerCpu) {
      $i++
      Write-Host "CPU$i $([math]::Round([double]$val, 2)) %"
    }
    $overall = (($cpuUsagePerCpu | Measure-Object -Average).Average)
    Write-Host "Overall average CPU Usage: $([math]::Round($overall, 2)) %"
  }
  else {
    Write-Host "CPU1 $([math]::Round([double]$cpuUsagePerCpu, 2)) %"
  }

  Write-Phase "Waiting for perf counter job (recv phase)"
  Wait-JobWithProgress -Job $script:perfCounterJob -Name 'Perf counters (recv)'
  $perfResults = Receive-Job -Job $script:perfCounterJob -Wait -AutoRemoveJob
  $script:perfCounterJob = $null
  $perfJsonPath = Join-Path $cwd 'quic_echo_server_perf_counters.json'
  $perfResults | ConvertTo-Json | Out-File -FilePath $perfJsonPath -Encoding utf8 -Force
  Write-Phase "Perf counter JSON written (recv phase): $perfJsonPath"

  # List json files in cwd
  Write-Host "JSON files in $cwd"
  # Log JSON file names and sizes (full contents available in uploaded artifacts)
  Get-ChildItem -Path $cwd -Filter *.json | ForEach-Object {
    Write-Host "  $($_.FullName) ($($_.Length) bytes)"
  }

  # Copy stats files to parent folder for GitHub Actions artifact upload
  if (Test-Path *.json) {
    Copy-Item -Path *.json -Destination $cwd\.. -Force
  }
  else {
    Write-Host "No JSON files found to copy."
  }

  Write-Host "QUIC echo tests completed successfully."
}
catch {
  Write-Host "QUIC echo tests failed."
  Write-Host $_
  $exitCode = 2
}
finally {
    # Best-effort WPR cancel in case inner try/finally was bypassed
    try { & wpr -cancel 2>$null } catch { }

    # Kill the specific local echo_server process if it's still running
    if ($script:serverProc -and -not $script:serverProc.HasExited) {
      Write-Warning "Cleaning up lingering echo_server (PID $($script:serverProc.Id))"
      Stop-Process -Id $script:serverProc.Id -Force -ErrorAction SilentlyContinue
    }

    # Stop any lingering CPU/perf counter background jobs
    foreach ($j in @($script:cpuMonitorJob, $script:perfCounterJob)) {
      if ($j -and $j.State -eq 'Running') {
        Write-Warning "Stopping leftover background job (Id=$($j.Id), Name=$($j.Name))"
        Stop-Job -Job $j -ErrorAction SilentlyContinue
        Remove-Job -Job $j -Force -ErrorAction SilentlyContinue
      }
    }

    # Clean up dev certificates
    Remove-QuicDevCert -Thumbprint $localCertThumbprint -StoreLocation $script:localCertStoreLocation
    if ($Session) {
      Remove-RemoteQuicDevCert -Session $Session -Thumbprint $remoteCertThumbprint -StoreLocation $script:remoteCertStoreLocation
    }

    if ($script:driverCodeSigningThumbprint) {
      certutil -delstore Root $script:driverCodeSigningThumbprint 2>$null | Out-Null
      certutil -delstore TrustedPublisher $script:driverCodeSigningThumbprint 2>$null | Out-Null
      certutil -delstore My $script:driverCodeSigningThumbprint 2>$null | Out-Null
      if ($Session) {
        Invoke-Command -Session $Session -ArgumentList $script:driverCodeSigningThumbprint -ScriptBlock {
          param($thumbprint)
          certutil -delstore Root $thumbprint 2>$null | Out-Null
          certutil -delstore TrustedPublisher $thumbprint 2>$null | Out-Null
        } -ErrorAction SilentlyContinue
      }
    }
    if ($script:driverCodeSigningCerPath -and (Test-Path -LiteralPath $script:driverCodeSigningCerPath)) {
      Remove-Item -LiteralPath $script:driverCodeSigningCerPath -Force -ErrorAction SilentlyContinue
    }

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
    Set-Service WinRM -StartupType Automatic
    Start-Service WinRM
    ```

  - If using PowerShell 7 session configuration, register it on the remote:
    ```powershell
    Register-PSSessionConfiguration -Name PowerShell.7 -RunAsCredential (Get-Credential) -Force
    ```

  - For HTTPS transport, create an HTTPS listener and configure an SSL cert
    for WinRM on the remote.  See `about_Remote_Troubleshooting`.

  Note: Adding hosts to TrustedHosts weakens authentication; prefer HTTPS or
  domain-joined Kerberos where possible.
#>
