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
    $toolFailure=$null
    try {
        if (-not $child.Process.WaitForExit($TimeoutSeconds*1000)) { throw 'Test tool deadline exceeded.' }
        $code=$child.Process.ExitCode
        if ($code -ne 0) {
            $error=[InvalidOperationException]::new("Test tool returned exit code $code.")
            $error.Data['ToolExitCode']=$code
            throw $error
        }
        $result=[pscustomobject]@{ ExitCode=$code }
    }catch{$toolFailure=$_;throw}
    finally {
        try{Close-ChurnChild $child}catch{
            if($null -eq $toolFailure){throw}
            $combined=[AggregateException]::new('The native tool and owned child cleanup both failed.',
                [Exception[]]@($toolFailure.Exception,$_.Exception))
            if($toolFailure.Exception.Data.Contains('ToolExitCode')){
                $combined.Data['ToolExitCode']=$toolFailure.Exception.Data['ToolExitCode']
            }
            $combined.Data['PrimaryDeadlineExceeded']=$toolFailure.Exception.Message -eq 'Test tool deadline exceeded.'
            throw $combined
        }
    }
    $result
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

function Invoke-WindowsEstablishedTransfer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Adapter,
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)][scriptblock]$Measure,
        [Parameter(Mandatory)]$MeasurementState
    )
    $failure=$null;$result=$null
    try {
        $overallBefore=Read-WindowsChurnCounters $Adapter.State $Plan
        $null=& $Adapter.StartPeer $Adapter.State $Plan
        $ready=[Diagnostics.Stopwatch]::StartNew()
        while(-not (& $Adapter.PeerReady $Adapter.State $Plan)) {
            if($ready.Elapsed.TotalSeconds -gt 20) { throw 'Established-transfer listener readiness deadline exceeded.' }
            Start-Sleep -Milliseconds 100
        }
        $state=$Adapter.State
        $state.Client=Start-ChurnChild $state.Executable $Plan.ClientArguments $state.Directory (Join-Path $state.Directory 'client')
        $ready.Restart()
        do {
            if($state.Client.Process.HasExited -or $state.Server.Process.HasExited) { throw 'Transfer exited before all connections established.' }
            $established=@(Get-NetTCPConnection -State Established -ErrorAction Stop|Where-Object{
                $_.OwningProcess -eq $state.Client.Process.Id -and $_.RemotePort -eq $Plan.Port
            }).Count
            if($established -eq $Plan.Connections) { break }
            if($ready.Elapsed.TotalSeconds -gt 30) { throw 'Not all persistent connections reached Established.' }
            Start-Sleep -Milliseconds 100
        } while($true)
        Start-Sleep -Seconds 3
        if($state.Client.Process.HasExited -or $state.Server.Process.HasExited) { throw 'Transfer exited during warmup.' }
        $before=Read-WindowsChurnCounters $state $Plan
        $MeasurementState.establishedAtStart=$established
        & $Measure $MeasurementState
        if($state.Client.Process.HasExited -or $state.Server.Process.HasExited) { throw 'Transfer exited inside the steady measurement window.' }
        $remaining=@(Get-NetTCPConnection -State Established -ErrorAction Stop|Where-Object{
            $_.OwningProcess -eq $state.Client.Process.Id -and $_.RemotePort -eq $Plan.Port
        }).Count
        if($remaining -ne $Plan.Connections) { throw 'Connections closed during steady measurement.' }
        $MeasurementState.establishedAtEnd=$remaining
        $after=Read-WindowsChurnCounters $state $Plan
        $MeasurementState.transmittedBytes=$after.Transmitted-$before.Transmitted
        $MeasurementState.receivedBytes=$after.Received-$before.Received
        if($MeasurementState.transmittedBytes -le 0 -or $MeasurementState.receivedBytes -le 0) { throw 'Persistent traffic made no wire progress.' }
        if(-not $state.Client.Process.WaitForExit(($Plan.Seconds+20)*1000)) { throw 'Persistent client did not finish within its deadline.' }
        if($state.Client.Process.ExitCode -ne 0) { throw 'Persistent client returned errors.' }
        $summary=ConvertFrom-CtsChurnOutput $state.Client.Output.GetAwaiter().GetResult()
        if($summary.Completed -ne $Plan.Connections -or $summary.NetworkErrors -ne 0 -or $summary.ProtocolErrors -ne 0) {
            throw 'Persistent transfer did not complete every connection without errors.'
        }
        $overallAfter=Read-WindowsChurnCounters $state $Plan
        $tx=$overallAfter.Transmitted-$overallBefore.Transmitted;$rx=$overallAfter.Received-$overallBefore.Received
        if($tx -lt $summary.SentBytes -or $rx -lt $summary.SentBytes) { throw 'Completed persistent payload was not accounted for by the selected pair.' }
        $result=[pscustomobject]@{connections=$summary.Completed;bytesSent=$summary.SentBytes
            adapterTransmitDelta=$tx;adapterReceiveDelta=$rx}
    } catch { $failure=$_ }
    finally {
        try { $null=& $Adapter.Close $Adapter.State $Plan }
        catch {
            if($null -ne $failure) { throw [AggregateException]::new('Established transfer and cleanup failed.',[Exception[]]@($failure.Exception,$_.Exception)) }
            throw
        }
    }
    if($null -ne $failure) { throw $failure }
    $result
}

function Invoke-WindowsChurnParallelBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string]$DiagnosticsDirectory,
        [Parameter(Mandatory)][string]$ClientInterface,
        [Parameter(Mandatory)][string]$ServerInterface,
        [Parameter(Mandatory)][ValidateCount(1,8)][object[]]$Plans
    )
    $adapters=[Collections.Generic.List[object]]::new()
    $bytes=0L;$connections=0L;$failure=$null;$result=$null
    try {
        foreach($plan in $Plans) {
            $directory=Join-Path $DiagnosticsDirectory "worker-$($adapters.Count)"
            $null=New-Item -ItemType Directory -Path $directory -ErrorAction Stop
            $adapter=New-WindowsCtsAdapter -Executable $Executable -DiagnosticsDirectory $directory `
                -ClientInterface $ClientInterface -ServerInterface $ServerInterface
            $adapters.Add($adapter)
            Start-WindowsChurnPeer $adapter.State $plan
        }
        foreach($index in 0..($Plans.Count-1)) {
            $ready=[Diagnostics.Stopwatch]::StartNew()
            while(-not (Test-WindowsChurnPeer $adapters[$index].State $Plans[$index])) {
                if($ready.Elapsed.TotalSeconds -gt 20) { throw 'Parallel healthy listener readiness deadline exceeded.' }
                Start-Sleep -Milliseconds 100
            }
        }
        $before=Read-WindowsChurnCounters $adapters[0].State $Plans[0]
        foreach($index in 0..($Plans.Count-1)) {
            $state=$adapters[$index].State
            $state.Client=Start-ChurnChild $state.Executable $Plans[$index].ClientArguments $state.Directory (Join-Path $state.Directory 'client')
        }
        $deadline=($Plans|Measure-Object Seconds -Maximum).Maximum+20
        $wait=[Diagnostics.Stopwatch]::StartNew()
        do {
            $active=$false
            foreach($adapter in $adapters) {
                if($adapter.State.Server.Process.HasExited) { throw 'Parallel healthy server exited during traffic.' }
                if(-not $adapter.State.Client.Process.HasExited) { $active=$true }
            }
            if(-not $active) { break }
            if($wait.Elapsed.TotalSeconds -gt $deadline) { throw 'Parallel healthy client deadline exceeded.' }
            Start-Sleep -Milliseconds 100
        } while($true)
        foreach($adapter in $adapters) {
            $client=$adapter.State.Client
            if($client.Process.ExitCode -ne 0) { throw 'Parallel healthy client exited with errors.' }
            $summary=ConvertFrom-CtsChurnOutput $client.Output.GetAwaiter().GetResult()
            if($summary.Completed -le 0 -or $summary.SentBytes -le 0 -or $summary.NetworkErrors -ne 0 -or $summary.ProtocolErrors -ne 0) {
                throw 'Parallel healthy traffic did not complete error-free.'
            }
            $bytes+=$summary.SentBytes;$connections+=$summary.Completed
        }
        $drain=[Diagnostics.Stopwatch]::StartNew()
        do {
            $after=Read-WindowsChurnCounters $adapters[0].State $Plans[0]
            $tx=$after.Transmitted-$before.Transmitted;$rx=$after.Received-$before.Received
            if($tx -ge $bytes -and $rx -ge $bytes) { break }
            if($drain.Elapsed.TotalSeconds -gt 5) { throw 'Parallel healthy bytes were not accounted for by the selected pair.' }
            Start-Sleep -Milliseconds 100
        } while($true)
        $result=[pscustomobject]@{connections=$connections;bytesSent=$bytes;adapterTransmitDelta=$tx;adapterReceiveDelta=$rx}
    } catch {
        $failure=$_
    } finally {
        $errors=[Collections.Generic.List[Exception]]::new()
        foreach($adapter in $adapters) {
            try { Close-WindowsChurn $adapter.State $null } catch { $errors.Add($_.Exception) }
        }
        if($errors.Count) {
            if($null -ne $failure) { $errors.Insert(0,$failure.Exception) }
            throw [AggregateException]::new('Parallel healthy process cleanup failed.',$errors)
        }
    }
    if($null -ne $failure) { throw $failure }
    $result
}

function Stop-TcpChurnCollector {
    param($Collector)
    Close-ChurnChild $Collector
}

function Start-RemoteChurnPeer($State,$Plan) {
    $State.PeerStarted=$true
    $State.PeerConfig=Invoke-Command -Session $State.Session -ErrorAction Stop -ScriptBlock {
        param($root,$plan,$client,$drop)
        Import-Module (Join-Path $root 'WindowsCts.psm1') -Force
        $global:OwnedChurnPeer=@{Handle=$null;Rules=@();Profiles=@()}
        if ($drop) {
            if ((Get-Service MpsSvc -ErrorAction Stop).Status -ne 'Running') { throw 'Peer firewall service is not running.' }
            $profiles=@(Get-NetFirewallProfile -ErrorAction Stop|Select-Object Name,Enabled)
            if (@($profiles|Where-Object{[string]$_.Enabled -notin @('True','False')}).Count) {
                throw 'Peer firewall profile state cannot be restored exactly.'
            }
            $global:OwnedChurnPeer.Profiles=$profiles
            $management='TcpChurnPeer-'+[guid]::NewGuid().ToString('N')
            $null=New-NetFirewallRule -Name $management -DisplayName $management -Direction Inbound -Action Allow `
                -Protocol TCP -LocalPort 5985,5986 -RemoteAddress $client -ErrorAction Stop
            $global:OwnedChurnPeer.Rules+=$management
        }
        foreach ($action in $(if($drop){@('Allow','Block')}else{@('Allow')})) {
            $rule='TcpChurnPeer-'+[guid]::NewGuid().ToString('N')
            $null=New-NetFirewallRule -Name $rule -DisplayName $rule -Direction Inbound -Action $action `
                -Protocol TCP -LocalPort $plan.Port -LocalAddress $plan.ServerAddress -RemoteAddress $client -ErrorAction Stop
            $global:OwnedChurnPeer.Rules+=$rule
        }
        if ($drop) {
            foreach($profile in $global:OwnedChurnPeer.Profiles) {
                if ([string]$profile.Enabled -eq 'False') { Set-NetFirewallProfile -Name $profile.Name -Enabled True -ErrorAction Stop }
            }
            if (@(Get-NetFirewallProfile -ErrorAction Stop|Where-Object{[string]$_.Enabled -ne 'True'}).Count) {
                throw 'Peer firewall policy did not enable the scoped fault.'
            }
        }
        $global:OwnedChurnPeer.Handle=Start-TcpChurnCollector -Program (Join-Path $root 'ctsTraffic.exe') `
            -Arguments $plan.ServerArguments -Directory $root -LogPrefix (Join-Path $root 'server')
        [pscustomobject]@{OriginallyEnabledProfiles=@($global:OwnedChurnPeer.Profiles|Where-Object{[string]$_.Enabled -eq 'True'}).Count
            TemporarilyEnabledProfiles=@($global:OwnedChurnPeer.Profiles|Where-Object{[string]$_.Enabled -eq 'False'}).Count}
    } -ArgumentList $State.PeerRoot,$Plan,$Plan.ClientAddress,$State.DropSyn
}

function Test-RemoteChurnPeer($State,$Plan) {
    Invoke-Command -Session $State.Session -ErrorAction Stop -ScriptBlock {
        param($port)
        if ($global:OwnedChurnPeer.Handle.Process.HasExited) { throw 'Owned peer server exited.' }
        @(Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object {
            $_.LocalPort -eq $port -and $_.OwningProcess -eq $global:OwnedChurnPeer.Handle.Process.Id
        }).Count -gt 0
    } -ArgumentList $Plan.Port
}

function Read-RemoteChurnCounters($State,$Plan) {
    $local=Get-NetAdapterStatistics -Name $State.ClientInterface -ErrorAction Stop
    $received=Invoke-Command -Session $State.Session -ErrorAction Stop -ScriptBlock {
        param($alias)
        (Get-NetAdapterStatistics -Name $alias -ErrorAction Stop).ReceivedBytes
    } -ArgumentList $State.PeerInterface
    [pscustomobject]@{Transmitted=[long]$local.SentBytes;Received=[long]$received}
}

function Invoke-RemoteChurnClient($State,$Plan) {
    $State.Client=Start-ChurnChild $State.Executable $Plan.ClientArguments $State.Directory (Join-Path $State.Directory 'client')
    if (-not $State.Client.Process.WaitForExit(($Plan.Seconds+20)*1000)) { throw 'Remote-pair client deadline exceeded.' }
    [pscustomobject]@{ExitCode=$State.Client.Process.ExitCode;Text=$State.Client.Output.GetAwaiter().GetResult()}
}

function Close-RemoteChurn($State,$Plan) {
    $failures=[Collections.Generic.List[Exception]]::new()
    if ($null -ne $State.Client) {
        try { Close-ChurnChild $State.Client } catch { $failures.Add($_.Exception) }
        finally { $State.Client=$null }
    }
    if ($State.PeerStarted) {
        try {
            Invoke-Command -Session $State.Session -ErrorAction Stop -ScriptBlock {
                $errors=[Collections.Generic.List[Exception]]::new()
                if ($null -ne $global:OwnedChurnPeer) {
                    if ($null -ne $global:OwnedChurnPeer.Handle) {
                        try { Stop-TcpChurnCollector $global:OwnedChurnPeer.Handle } catch { $errors.Add($_.Exception) }
                    }
                    $profilesRestored=$true
                    foreach($profile in $global:OwnedChurnPeer.Profiles) {
                        try { Set-NetFirewallProfile -Name $profile.Name -Enabled $profile.Enabled -ErrorAction Stop }
                        catch { $errors.Add($_.Exception);$profilesRestored=$false }
                    }
                    $effective=@(Get-NetFirewallProfile -ErrorAction Stop)
                    foreach($profile in $global:OwnedChurnPeer.Profiles) {
                        $actual=@($effective|Where-Object Name -eq $profile.Name)
                        if($actual.Count -ne 1 -or [string]$actual[0].Enabled -ne [string]$profile.Enabled) {
                            $errors.Add([InvalidOperationException]::new('Peer firewall state differs after restoration.'))
                            $profilesRestored=$false
                        }
                    }
                    if (-not $profilesRestored) { throw [AggregateException]::new('Peer profile restoration failed; scoped recovery rules retained.',$errors) }
                    foreach($rule in $global:OwnedChurnPeer.Rules) {
                        try { Remove-NetFirewallRule -Name $rule -ErrorAction Stop } catch { $errors.Add($_.Exception) }
                    }
                    $global:OwnedChurnPeer=$null
                }
                if ($errors.Count) { throw [AggregateException]::new('Owned peer cleanup failed.',$errors) }
            } | Out-Null
        } catch { $failures.Add($_.Exception) }
        finally { $State.PeerStarted=$false }
    }
    if ($failures.Count) { throw [AggregateException]::new('Remote-pair cleanup failed.',$failures) }
}

function New-RemoteWindowsCtsAdapter {
    param($Executable,$DiagnosticsDirectory,$ClientInterface,$PeerInterface,$PeerSession,$PeerRoot,[bool]$DropSyn)
    @{
        State=@{Executable=$Executable;Directory=$DiagnosticsDirectory;ClientInterface=$ClientInterface
            PeerInterface=$PeerInterface;Session=$PeerSession;PeerRoot=$PeerRoot;DropSyn=$DropSyn;Client=$null;PeerStarted=$false;PeerConfig=$null}
        StartPeer=${function:Start-RemoteChurnPeer};PeerReady=${function:Test-RemoteChurnPeer}
        ReadCounters=${function:Read-RemoteChurnCounters};RunClient=${function:Invoke-RemoteChurnClient};Close=${function:Close-RemoteChurn}
    }
}

Export-ModuleMember -Function New-WindowsCtsAdapter,New-RemoteWindowsCtsAdapter,Invoke-TcpChurnTool,Start-TcpChurnCollector,Stop-TcpChurnCollector,Invoke-WindowsChurnParallelBatch,Invoke-WindowsEstablishedTransfer
