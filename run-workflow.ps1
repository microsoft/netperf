param (
    [Parameter(Mandatory = $true)]
    [string]$type,

    [Parameter(Mandatory = $true)]
    [string]$name, # Deprecated, no longer used

    [Parameter(Mandatory = $true)]
    [string]$ref,

    [Parameter(Mandatory = $true)]
    [string]$sha,

    [Parameter(Mandatory = $true)]
    [string]$pat,

    [Parameter(Mandatory = $false)]
    [string]$run_id = ""
)

Set-StrictMode -Version 'Latest'
$PSDefaultParameterValues['*:ErrorAction'] = 'Stop'

$headers = @{
    "Accept" = "application/vnd.github+json"
    "Authorization" = "Bearer $pat"
    "X-GitHub-Api-Version" = "2022-11-28"
}

$guid = (New-Guid).ToString()

function Start-Workflow {
    $url = "https://api.github.com/repos/microsoft/netperf/dispatches"
    $body = @{
        event_type = "run-$type"
        client_payload = @{
            guid = $guid
            ref = $ref
            sha = $sha
            run_id = $run_id
        }
    } | ConvertTo-Json
    Write-Debug "POST $body to $url"
    $result = Invoke-WebRequest -Uri $url -Method POST -Headers $headers -Body $body
}

function Get-Runs {
    $url = "https://api.github.com/repos/microsoft/netperf/actions/runs?event=repository_dispatch"
    Write-Debug "GET $url"
    return ((Invoke-WebRequest -Uri $url -Method GET -Headers $headers).Content | ConvertFrom-Json).workflow_runs
}

function Get-Run {
    param([string]$runId)
    $url = "https://api.github.com/repos/microsoft/netperf/actions/runs/$runId"
    Write-Debug "GET $url"
    return (Invoke-WebRequest -Uri $url -Method GET -Headers $headers).Content | ConvertFrom-Json
}

function Get-Jobs {
    param([string]$runId)
    $url = "https://api.github.com/repos/microsoft/netperf/actions/runs/$runId/jobs"
    Write-Debug "GET $url"
    return ((Invoke-WebRequest -Uri $url -Method GET -Headers $headers).Content | ConvertFrom-Json).jobs
}

function Get-RunId {
    for ($i = 0; $i -lt 3; $i++) { # Try up to 3 times
        $workflows = Get-Runs
        foreach ($workflow in $workflows) {
            $jobs = Get-Jobs $workflow.id
            foreach ($job in $jobs) {
                if ($job.name.Contains($guid)) {
                    return $workflow.id
                }
            }
        }
        Write-Host "Run not found, retrying in 1 second..."
        Start-Sleep -Seconds 1
    }
    Write-Error "Run not found!"
    return $null
}

function Get-RunStatus {
    param([string]$id)
    $run = Get-Run $id
    if ($run.status -ne "completed") {
        return $false
    }
    if ($run.conclusion -ne "success") {
        Write-Error "Run completed with status $($run.conclusion)!"
    }
    return $true
}

function Wait-ForRun {
    param([string]$id)
    for ($i = 0; $i -lt 120; $i++) { # 120 * 30 sec = 1 hour
        if (Get-RunStatus $id) {
            return
        }
        Start-Sleep -Seconds 30
    }
    Write-Error "Run timed out!"
}

# Start the new workflow run.
Write-Host "Triggering new workflow ($guid)..."
Start-Workflow

# Find the workflow run.
Write-Host "Looking for workflow run..."
$id = Get-RunId
Write-Host "Found: https://github.com/microsoft/netperf/actions/runs/$id"

# Wait for the run to complete.
Write-Host "Waiting for run to complete..."
Wait-ForRun $id
Write-Host "Run succeeded!"
