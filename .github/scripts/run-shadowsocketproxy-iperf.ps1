param(
  [Parameter(Mandatory = $true)][string]$TargetPeer,
  [Parameter(Mandatory = $true)][string]$TargetAddress,
  [Parameter(Mandatory = $true)][string]$ShadowRoot,
  [Parameter(Mandatory = $true)][string]$Distribution,
  [string]$Iperf3WslPath = '/usr/bin/iperf3',
  [string]$Iperf3WindowsPath = 'C:\_work\iperf3\iperf3.exe',
  [int]$Duration = 30,
  [int]$Runs = 3,
  [string]$UdpRates = '100M,1G',
  [switch]$SkipProxy
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-WslChecked {
  param([Parameter(Mandatory = $true)][string[]]$Arguments)
  $output = & wsl.exe @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "WSL command failed: wsl.exe $($Arguments -join ' ')"
  }
  return (($output | Out-String).Trim() -replace "`0", '')
}

function ConvertTo-WslPath {
  param([Parameter(Mandatory = $true)][string]$WindowsPath)
  $fullPath = (Resolve-Path -LiteralPath $WindowsPath).Path
  if ($fullPath -notmatch '^([A-Za-z]):\\(.*)$') {
    throw "Expected a drive-qualified Windows path: $fullPath"
  }
  return "/mnt/$($Matches[1].ToLowerInvariant())/$($Matches[2] -replace '\\', '/')"
}

function Wait-TcpPort {
  param(
    [Parameter(Mandatory = $true)][string]$Address,
    [Parameter(Mandatory = $true)][int]$Port
  )
  for ($attempt = 0; $attempt -lt 30; $attempt++) {
    if (Test-NetConnection -ComputerName $Address -Port $Port -InformationLevel Quiet) {
      return
    }
    Start-Sleep -Milliseconds 500
  }
  throw "TCP port $Address`:$Port did not become ready"
}

function Wait-WindowsTcpListener {
  param([Parameter(Mandatory = $true)][int]$Port)
  for ($attempt = 0; $attempt -lt 30; $attempt++) {
    if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) {
      return
    }
    Start-Sleep -Milliseconds 500
  }
  throw "No Windows TCP listener appeared on port $Port"
}

function Start-ShadowProxy {
  param(
    [Parameter(Mandatory = $true)][string]$ControlBinary,
    [Parameter(Mandatory = $true)][string]$HostBinary,
    [Parameter(Mandatory = $true)][string]$BpfObject,
    [Parameter(Mandatory = $true)][string]$WorkDirectory
  )

  $route = Invoke-WslChecked @('-d', $Distribution, '--', 'ip', 'route', 'show', 'default') -split '\s+'
  if ($route.Count -lt 5) {
    throw 'Unable to discover the WSL default gateway and interface'
  }
  $gateway = $route[2]
  $interface = $route[4]
  $controlWsl = ConvertTo-WslPath $ControlBinary
  $bpfWsl = ConvertTo-WslPath $BpfObject
  $secret = [Convert]::ToHexString([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
  $identity = "ssp-iperf-$([guid]::NewGuid().ToString('N'))"
  $controlPort = 50051
  $proxyPort = 15000
  $proxyAddress = "${gateway}:$proxyPort"
  $controlStdout = Join-Path $WorkDirectory 'control.stdout.log'
  $controlStderr = Join-Path $WorkDirectory 'control.stderr.log'
  $proxyStdout = Join-Path $WorkDirectory 'host-proxy.stdout.log'
  $proxyStderr = Join-Path $WorkDirectory 'host-proxy.stderr.log'
  $qdiscCreated = $false
  $controlProcess = $null
  $proxyProcess = $null

  try {
    $qdisc = Invoke-WslChecked @('-d', $Distribution, '-u', 'root', '--', 'tc', 'qdisc', 'show', 'dev', $interface)
    if ($qdisc -notmatch '(?m)^qdisc clsact ') {
      Invoke-WslChecked @('-d', $Distribution, '-u', 'root', '--', 'tc', 'qdisc', 'add', 'dev', $interface, 'clsact') | Out-Null
      $qdiscCreated = $true
    }

    $controlArguments = @(
      '-d', $Distribution, '-u', 'root', '--', 'env',
      "SSP_LISTEN_ADDR=127.0.0.1:$controlPort",
      'SSP_TC_HOOK_LAYOUT=wsl',
      "SSP_TLS_PSK_IDENTITY=$identity",
      "SSP_TLS_PSK_SECRET=$secret",
      $controlWsl
    )
    $controlProcess = Start-Process wsl.exe -PassThru -WindowStyle Hidden `
      -RedirectStandardOutput $controlStdout -RedirectStandardError $controlStderr `
      -ArgumentList $controlArguments
    Wait-TcpPort -Address '127.0.0.1' -Port $controlPort

    $proxyArguments = @(
      '--listen', $proxyAddress,
      '--control-endpoint', "https://127.0.0.1:$controlPort",
      '--psk-identity', $identity,
      '--psk-secret', $secret,
      '--bpf-elf', $bpfWsl,
      '--interface', $interface,
      '--udp-idle-timeout-secs', ([Math]::Max(60, $Duration + 30))
    )
    $proxyProcess = Start-Process $HostBinary -PassThru -WindowStyle Hidden `
      -RedirectStandardOutput $proxyStdout -RedirectStandardError $proxyStderr `
      -ArgumentList $proxyArguments
    # Windows may not be able to connect back through the WSL gateway address,
    # even though WSL applications can reach the host-owned listener.
    Wait-WindowsTcpListener -Port $proxyPort
    if ($proxyProcess.HasExited) {
      throw "ShadowSocketProxy host process exited with code $($proxyProcess.ExitCode)"
    }

    return [pscustomobject]@{
      Gateway = $gateway
      Interface = $interface
      ControlProcess = $controlProcess
      ProxyProcess = $proxyProcess
      QdiscCreated = $qdiscCreated
      ControlStdout = $controlStdout
      ControlStderr = $controlStderr
      ProxyStdout = $proxyStdout
      ProxyStderr = $proxyStderr
      Distribution = $Distribution
    }
  }
  catch {
    if (Test-Path -LiteralPath $controlStderr) { Get-Content -LiteralPath $controlStderr }
    if (Test-Path -LiteralPath $proxyStderr) { Get-Content -LiteralPath $proxyStderr }
    if ($null -ne $proxyProcess -and -not $proxyProcess.HasExited) { Stop-Process -Id $proxyProcess.Id -Force }
    if ($null -ne $controlProcess -and -not $controlProcess.HasExited) { Stop-Process -Id $controlProcess.Id -Force }
    if ($qdiscCreated) {
      Invoke-WslChecked @('-d', $Distribution, '-u', 'root', '--', 'tc', 'qdisc', 'del', 'dev', $interface, 'clsact') | Out-Null
    }
    throw
  }
}

function Stop-ShadowProxy {
  param([Parameter(Mandatory = $true)]$State)
  if ($null -ne $State.ProxyProcess -and -not $State.ProxyProcess.HasExited) {
    Stop-Process -Id $State.ProxyProcess.Id -Force
  }
  if ($null -ne $State.ControlProcess -and -not $State.ControlProcess.HasExited) {
    Stop-Process -Id $State.ControlProcess.Id -Force
  }
  if ($State.QdiscCreated) {
    Invoke-WslChecked @('-d', $State.Distribution, '-u', 'root', '--', 'tc', 'qdisc', 'del', 'dev', $State.Interface, 'clsact') | Out-Null
  }
}

function Invoke-Iperf {
  param(
    [Parameter(Mandatory = $true)][string]$Scenario,
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [Parameter(Mandatory = $true)][string]$OutputPath
  )
  $wslArguments = @('-d', $Distribution, '--', $Iperf3WslPath) + $Arguments
  $json = Invoke-WslChecked -Arguments $wslArguments
  $json | Out-File -LiteralPath $OutputPath -Encoding utf8 -Force
  try {
    $parsed = $json | ConvertFrom-Json
    [pscustomobject]@{
      Scenario = $Scenario
      Output = $OutputPath
      SentBps = $parsed.end.sum_sent.bits_per_second
      ReceivedBps = $parsed.end.sum_received.bits_per_second
      LostPercent = $parsed.end.sum.lost_percent
      JitterMs = $parsed.end.sum.jitter_ms
    }
  }
  catch {
    throw "iperf3 did not produce valid JSON for $Scenario. Raw output saved to $OutputPath"
  }
}

$workDirectory = Join-Path (Get-Location) 'shadowsocketproxy-iperf'
New-Item -ItemType Directory -Force -Path $workDirectory | Out-Null
$session = $null
$serverProcessId = $null
$proxyState = $null

try {
  $shadowRootPath = (Resolve-Path -LiteralPath $ShadowRoot).Path
  $controlBinary = Join-Path $shadowRootPath 'target\release\shadow-socket-proxy-control'
  $hostBinary = Join-Path $shadowRootPath 'target\release\shadow-socket-proxy-host.exe'
  $bpfObject = Join-Path $shadowRootPath 'crates\bpf\shadow-socket-proxy.bpf.o'
  foreach ($path in @($controlBinary, $hostBinary, $bpfObject)) {
    if (-not (Test-Path -LiteralPath $path)) {
      throw "Required ShadowSocketProxy artifact is missing: $path"
    }
  }

  Invoke-WslChecked @('-d', $Distribution, '--', 'test', '-x', $Iperf3WslPath) | Out-Null
  $modulePath = Join-Path $PSScriptRoot 'performance_utilities.psm1'
  Import-Module $modulePath -Force
  $session = Create-Session -PeerName $TargetPeer -RemotePSConfiguration 'PowerShell.7'
  $remoteDirectory = Split-Path -Parent $Iperf3WindowsPath
  Invoke-Command -Session $session -ScriptBlock {
    param($directory, $iperfPath)
    if (-not (Test-Path -LiteralPath $directory)) {
      New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $iperfPath)) {
      throw "iperf3 is missing on target peer: $iperfPath"
    }
    Get-NetFirewallRule -DisplayName 'netperf-iperf3-*' -ErrorAction SilentlyContinue |
      Remove-NetFirewallRule -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName 'netperf-iperf3-tcp' -Direction Inbound -Protocol TCP -LocalPort 5201 -Action Allow | Out-Null
    New-NetFirewallRule -DisplayName 'netperf-iperf3-udp' -Direction Inbound -Protocol UDP -LocalPort 5201 -Action Allow | Out-Null
    $process = Start-Process -FilePath $iperfPath -ArgumentList @('-s') -PassThru -WindowStyle Hidden
    return $process.Id
  } -ArgumentList $remoteDirectory, $Iperf3WindowsPath | ForEach-Object {
    if ($_ -is [int]) { $script:serverProcessId = $_ }
  }
  if ($null -eq $serverProcessId) {
    throw 'Unable to start iperf3 on the target peer'
  }

  $results = [System.Collections.Generic.List[object]]::new()
  $runArguments = @(
    @('-c', $TargetAddress, '-t', $Duration, '-J'),
    @('-c', $TargetAddress, '-t', $Duration, '-P', '4', '-J')
  )
  foreach ($run in 1..$Runs) {
    foreach ($args in $runArguments) {
      $name = if ($args -contains '-P') { 'tcp-parallel' } else { 'tcp' }
      $path = Join-Path $workDirectory "baseline-$name-run$run.json"
      $results.Add((Invoke-Iperf -Scenario "baseline-$name-run$run" -Arguments $args -OutputPath $path))
    }
    foreach ($rate in ($UdpRates -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
      $args = @('-c', $TargetAddress, '-u', '-b', $rate, '-t', $Duration, '-J')
      $path = Join-Path $workDirectory "baseline-udp-$rate-run$run.json"
      $results.Add((Invoke-Iperf -Scenario "baseline-udp-$rate-run$run" -Arguments $args -OutputPath $path))
    }
  }

  if (-not $SkipProxy) {
    $proxyState = Start-ShadowProxy `
      -ControlBinary $controlBinary `
      -HostBinary $hostBinary `
      -BpfObject $bpfObject `
      -WorkDirectory $workDirectory

    foreach ($run in 1..$Runs) {
      foreach ($args in $runArguments) {
        $name = if ($args -contains '-P') { 'tcp-parallel' } else { 'tcp' }
        $path = Join-Path $workDirectory "proxy-$name-run$run.json"
        $results.Add((Invoke-Iperf -Scenario "proxy-$name-run$run" -Arguments $args -OutputPath $path))
      }
      foreach ($rate in ($UdpRates -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        $args = @('-c', $TargetAddress, '-u', '-b', $rate, '-t', $Duration, '-J')
        $path = Join-Path $workDirectory "proxy-udp-$rate-run$run.json"
        $results.Add((Invoke-Iperf -Scenario "proxy-udp-$rate-run$run" -Arguments $args -OutputPath $path))
      }
    }
  }

  $results | ConvertTo-Json -Depth 4 | Out-File -LiteralPath (Join-Path $workDirectory 'summary.json') -Encoding utf8 -Force
}
finally {
  if ($null -ne $proxyState) {
    Stop-ShadowProxy -State $proxyState
  }
  if ($null -ne $session) {
    if ($null -ne $serverProcessId) {
      Invoke-Command -Session $session -ScriptBlock {
        param($processId)
        Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
        Get-NetFirewallRule -DisplayName 'netperf-iperf3-*' -ErrorAction SilentlyContinue |
          Remove-NetFirewallRule -ErrorAction SilentlyContinue
      } -ArgumentList $serverProcessId -ErrorAction SilentlyContinue
    }
    Remove-PSSession -Session $session -ErrorAction SilentlyContinue
  }
}
