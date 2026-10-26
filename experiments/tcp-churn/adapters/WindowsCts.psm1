# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.2
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Start-ChurnChild($Program, [string[]]$Arguments, $Directory, $LogPrefix) {
    $settings=[Diagnostics.ProcessStartInfo]::new()
    $settings.FileName=$Program
    $settings.WorkingDirectory=$Directory
    $settings.UseShellExecute=$false
    $settings.RedirectStandardOutput=$true
    $settings.RedirectStandardError=$true
    foreach ($item in $Arguments) { $settings.ArgumentList.Add($item) }
    $child=[Diagnostics.Process]::new()
    $child.StartInfo=$settings
    if (-not $child.Start()) { throw 'Unable to launch test tool.' }
    @{
        Process=$child; Output=$child.StandardOutput.ReadToEndAsync()
        Error=$child.StandardError.ReadToEndAsync(); LogPrefix=$LogPrefix
    }
}

function Close-ChurnChild($Child) {
    if ($null -eq $Child) { return }
    try {
        if (-not $Child.Process.HasExited) {
            try { Stop-Process -Id $Child.Process.Id -Force -ErrorAction Stop }
            catch [Microsoft.PowerShell.Commands.ProcessCommandException] {
                if (-not $Child.Process.HasExited) { throw }
                Write-Verbose 'Owned child exited before termination.'
            }
        }
        if (-not $Child.Process.WaitForExit(10000)) { throw 'Owned child did not terminate.' }
        [IO.File]::WriteAllText("$($Child.LogPrefix).out.txt",$Child.Output.GetAwaiter().GetResult())
        [IO.File]::WriteAllText("$($Child.LogPrefix).err.txt",$Child.Error.GetAwaiter().GetResult())
    } finally { $Child.Process.Dispose() }
}

function Invoke-TcpChurnTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Program,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$LogPrefix,
        [ValidateRange(1,600)][int]$TimeoutSeconds=60
    )
    $child=Start-ChurnChild $Program $Arguments $Directory $LogPrefix
    try {
        if (-not $child.Process.WaitForExit($TimeoutSeconds*1000)) { throw 'Test tool deadline exceeded.' }
        $code=$child.Process.ExitCode
        if ($code -ne 0) {
            $error=[InvalidOperationException]::new("Test tool returned exit code $code.")
            $error.Data['ToolExitCode']=$code
            throw $error
        }
        [pscustomobject]@{ ExitCode=$code }
    } finally { Close-ChurnChild $child }
}

function Start-WindowsChurnPeer($State,$Plan) {
    $State.Server=Start-ChurnChild $State.Executable $Plan.ServerArguments $State.Directory (Join-Path $State.Directory 'server')
}

function Test-WindowsChurnPeer($State,$Plan) {
    if ($State.Server.Process.HasExited) { throw 'CTS server exited before readiness.' }
    $rows=@(Get-NetTCPConnection -State Listen -ErrorAction Stop |
        Where-Object { $_.OwningProcess -eq $State.Server.Process.Id -and $_.LocalPort -eq $Plan.Port })
    return $rows.Count -gt 0
}

function Read-WindowsChurnCounters($State,$Plan) {
    $sender=Get-NetAdapterStatistics -Name $State.ClientInterface -ErrorAction Stop
    $receiver=Get-NetAdapterStatistics -Name $State.ServerInterface -ErrorAction Stop
    [pscustomobject]@{ Transmitted=[long]$sender.SentBytes; Received=[long]$receiver.ReceivedBytes }
}

function Invoke-WindowsChurnClient($State,$Plan) {
    $State.Client=Start-ChurnChild $State.Executable $Plan.ClientArguments $State.Directory (Join-Path $State.Directory 'client')
    $deadline=[Diagnostics.Stopwatch]::StartNew()
    while (-not $State.Client.Process.WaitForExit(100)) {
        if ($State.Server.Process.HasExited) { throw 'CTS server exited while traffic was active.' }
        if ($deadline.Elapsed.TotalSeconds -gt $Plan.Seconds+20) { throw 'CTS client deadline exceeded.' }
    }
    [pscustomobject]@{ ExitCode=$State.Client.Process.ExitCode; Text=$State.Client.Output.GetAwaiter().GetResult() }
}

function Close-WindowsChurn($State,$Plan) {
    $errors=[Collections.Generic.List[Exception]]::new()
    foreach ($name in @('Client','Server')) {
        if ($null -ne $State[$name]) {
            try { Close-ChurnChild $State[$name] }
            catch { $errors.Add($_.Exception) }
            finally { $State[$name]=$null }
        }
    }
    if ($errors.Count) { throw [AggregateException]::new('Owned CTS cleanup failed.',$errors) }
}

function New-WindowsCtsAdapter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string]$DiagnosticsDirectory,
        [Parameter(Mandatory)][string]$ClientInterface,
        [Parameter(Mandatory)][string]$ServerInterface
    )
    foreach ($alias in @($ClientInterface,$ServerInterface)) {
        if ([string]::IsNullOrWhiteSpace($alias) -or $alias -match '[*?\[\]\r\n]') {
            throw 'Use exact interface aliases.'
        }
    }
    if ($ClientInterface -eq $ServerInterface) { throw 'Two distinct adapters are required.' }
    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) { throw 'CTS executable is missing.' }
    if (-not (Test-Path -LiteralPath $DiagnosticsDirectory -PathType Container)) { throw 'Diagnostics directory is missing.' }
    @{
        State=@{
            Executable=[IO.Path]::GetFullPath($Executable); Directory=[IO.Path]::GetFullPath($DiagnosticsDirectory)
            ClientInterface=$ClientInterface; ServerInterface=$ServerInterface
            Client=$null; Server=$null
        }
        StartPeer=${function:Start-WindowsChurnPeer}
        PeerReady=${function:Test-WindowsChurnPeer}
        ReadCounters=${function:Read-WindowsChurnCounters}
        RunClient=${function:Invoke-WindowsChurnClient}
        Close=${function:Close-WindowsChurn}
    }
}

function Start-TcpChurnCollector {
    param($Program,[string[]]$Arguments,$Directory,$LogPrefix)
    Start-ChurnChild $Program $Arguments $Directory $LogPrefix
}

function Stop-TcpChurnCollector {
    param($Collector)
    Close-ChurnChild $Collector
}

Export-ModuleMember -Function New-WindowsCtsAdapter,Invoke-TcpChurnTool,Start-TcpChurnCollector,Stop-TcpChurnCollector
