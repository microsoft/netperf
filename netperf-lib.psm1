
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
        [string]$Command
    )
    Write-Host "Sending command: $Command"
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
        [scriptblock]$UnblockRoutine = {}
    )

    for ($i = 0; $i -lt $maxattempts; $i++) {
        $UnblockRoutine.Invoke()
        Start-Sleep -Seconds $WaitPerAttempt
        $headers = @{
            "secret" = "$env:netperf_syncer_secret"
        }
        $url = "$env:netperf_api_url"
        $RunId = "$env:netperf_run_id"
        $Response = Invoke-WebRequest -Uri "$url/getkeyvalue?key=$RunId" -Headers $headers -UseBasicParsing
        if (!($Response.StatusCode -eq 200)) {
            throw "Remote Cache State Not Set!"
        }
        $CurrState = $Response.Content | ConvertFrom-Json
        if ($CurrState.value.SeqNum -eq $CurrState.value.Commands.Count) {
            return
        }
    }

    throw "Server did not finish execution in time! Tried $maxattempts times with $waittime seconds interval."
}


