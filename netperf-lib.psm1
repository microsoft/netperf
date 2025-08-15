
function ValidateInheritedParams {
    Write-Host "Inherited run id: $env:netperf_run_id"
    Write-Host "Inherited role: $env:netperf_role"
    Write-Host "Inherited remote_powershell_supported: $env:netperf_remote_powershell_supported"
    Write-Host "Inherited api url: $env:netperf_api_url"
    $headers = @{
        'secret' = $env:netperf_syncer_secret
    }
    Invoke-WebRequest -Uri "$env:netperf_api_url/hello" -Headers $headers
}

function NetperfSendCommand {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Command,
        [Parameter(Mandatory = $false)]
        $Session
    )

    if ($Session -and $Session -ne "NOT_SUPPORTED") {
        $CallBackName = $env:CallBackName
        $RemoteDir = $env:RemoteDir
        if ($isWindows) {
            Write-Host "Sending command (via remote powershell): $RemoteDir/scripts/$CallBackName -Command $Command -WorkingDir $RemoteDir"
            Invoke-Command -Session $Session -ScriptBlock {
                & "$Using:RemoteDir/scripts/$Using:CallBackName" -Command $Using:Command -WorkingDir $Using:RemoteDir
            }
        } else {
            Write-Host "Sending command (via remote powershell): sudo -n pwsh -NoProfile -NonInteractive -File $RemoteDir/scripts/$CallBackName -Command $Command -WorkingDir $RemoteDir"
            Invoke-Command -Session $Session -ScriptBlock {
                & sudo -n pwsh -NoProfile -NonInteractive -File `
                "$Using:RemoteDir/scripts/$Using:CallBackName" `
                -Command $Using:Command `
                -WorkingDir $Using:RemoteDir
            }
        }
        return
    }


    Write-Host "Sending command (via remote cache): $Command"
    # Should send a command to the shared cache and wait for the server process to execute said command before exiting.
    $headers = @{
        "secret" = "$env:netperf_syncer_secret"
    }
    $url = "$env:netperf_api_url"
    $RunId = "$env:netperf_run_id"
    try {
        $Response = Invoke-WebRequest -Uri "$url/getkeyvalue?key=$RunId" -Headers $headers -UseBasicParsing
    } catch {
        Write-Host "Unable to fetch state. Creating a new one now."
        $state = [pscustomobject]@{
            value=[pscustomobject]@{
            "SeqNum" = 0
            "Commands" = @($Command)
        }}
        $StateJson = $state | ConvertTo-Json
        $Response = Invoke-WebRequest -Uri "$url/setkeyvalue?key=$RunId" -Headers $headers -Method Post -Body $StateJson -ContentType "application/json" -UseBasicParsing
        if ($Response.StatusCode -ne 200) {
            throw "Failed to set the key value!"
        }
        return
    }
    $CurrState = $Response.Content | ConvertFrom-Json
    $CurrState.Commands += $Command
    $CurrState = [pscustomobject]@{
        value=$CurrState
    }
    $StateJson = $CurrState | ConvertTo-Json
    $Response = Invoke-WebRequest -Uri "$url/setkeyvalue?key=$RunId" -Headers $headers -Method Post -Body $StateJson -ContentType "application/json" -UseBasicParsing
    if ($Response.StatusCode -ne 200) {
        throw "Failed to set the key value!"
    }
}

function NetperfWaitServerFinishExecution {
    param (
        [Parameter(Mandatory = $false)]
        [int]$MaxAttempts = 30,
        [Parameter(Mandatory = $false)]
        [int]$WaitPerAttempt = 8,
        [Parameter(Mandatory = $false)]
        [scriptblock]$UnblockRoutine = {},
        [Parameter(Mandatory = $false)]
        $Session
    )
    if ($Session -and $Session -ne "NOT_SUPPORTED") {
        Write-Host "No need to wait if we are doing remote powershell..."
        return
    }
    for ($i = 0; $i -lt $maxattempts; $i++) {
        $UnblockRoutine.Invoke()
        Write-Host "Waiting for server to finish execution... Attempt $i"
        Start-Sleep -Seconds $WaitPerAttempt
        $headers = @{
            "secret" = "$env:netperf_syncer_secret"
        }
        $url = "$env:netperf_api_url"
        $RunId = "$env:netperf_run_id"
        try {
            $Response = Invoke-WebRequest -Uri "$url/getkeyvalue?key=$RunId" -Headers $headers -UseBasicParsing
            if (!($Response.StatusCode -eq 200)) {
                throw "Remote Cache State Not Set!"
            }
        } catch {
            Write-Host "Failed to fetch state. Retrying... Error: $_"
            continue
        }

        $CurrState = $Response.Content | ConvertFrom-Json
        if ($CurrState.SeqNum -eq $CurrState.Commands.Count) {
            return
        } else {
            Write-Host "Server not done yet. Seq num: $($CurrState.SeqNum), Commands count: $($CurrState.Commands.Count)"
        }
    }

    throw "Server did not finish execution in time! Tried $maxattempts times with $WaitPerAttempt seconds interval."
}


function InitNetperfLib {
    param (
        $CallBackName,
        $RemoteDir,
        $RemoteName,
        $UserNameOnLinux
    )
    $env:CallBackName = $CallBackName
    $env:RemoteDir = $RemoteDir
    $env:RemoteName = $RemoteName
    $env:UserNameOnLinux = $UserNameOnLinux
    $RemotePowershellSupported = $env:netperf_remote_powershell_supported
    if ($RemotePowershellSupported -eq $true) {

        # Set up the connection to the peer over remote powershell.
        Write-Host "Connecting to $RemoteName"
        Write-Host "Using Callback Script: $RemoteDir/scripts/$CallBackName"
        $Attempts = 0
        while ($Attempts -lt 5) {
            try {
                if ($isWindows) {
                    $username = (Get-ItemProperty 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon').DefaultUserName
                    $password = (Get-ItemProperty 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon').DefaultPassword | ConvertTo-SecureString -AsPlainText -Force
                    $cred = New-Object System.Management.Automation.PSCredential ($username, $password)
                    $Session = New-PSSession -ComputerName $RemoteName -Credential $cred -ConfigurationName PowerShell.7
                } else {
                    $Session = New-PSSession -HostName $RemoteName -UserName $UserNameOnLinux -SSHTransport
                }
                break
            } catch {
                Write-Host "Error $_"
                $Attempts += 1
                Start-Sleep -Seconds 10
            }
        }

        if ($null -eq $Session) {
            Write-GHError "Failed to create remote session"
            exit 1
        }

    } else {
        $Session = "NOT_SUPPORTED"
        Write-Host "Remote PowerShell is not supported in this environment"
    }
    return $Session
}

function Copy-RepoToPeer {
    param($Session)
    $RemoteDir = $env:RemoteDir
    if (!($Session -eq "NOT_SUPPORTED")) {
        # Copy the artifacts to the peer.
        Write-Host "Copying files to peer"
        Invoke-Command -Session $Session -ScriptBlock {
            if (Test-Path $Using:RemoteDir) {
                Remove-Item -Force -Recurse $Using:RemoteDir | Out-Null
            }
            New-Item -ItemType Directory -Path $Using:RemoteDir -Force | Out-Null
        }
        Copy-Item -ToSession $Session -Path ./*, ./.* -Destination "$RemoteDir" -Recurse -Force
    } else {
        Write-Host "Not using remote powershell, assuming peer has checked out the repo."
    }
}
