param (
    [Parameter(Mandatory = $true)]
    [string]$type,

    [Parameter(Mandatory = $true)]
    [string]$name,

    [Parameter(Mandatory = $true)]
    [string]$ref,

    [Parameter(Mandatory = $true)]
    [string]$sha,
    
    [Parameter(Mandatory = $true)]
    [string]$pat
)

Set-StrictMode -Version 'Latest'
$PSDefaultParameterValues['*:ErrorAction'] = 'Stop'

$headers = @{
    "Accept" = "application/vnd.github+json"
    "Authorization" = "Bearer $pat"
    "X-GitHub-Api-Version" = "2022-11-28"
}

function Start-Workflow {
    param([string]$headers, [string]$name, [string]$ref, [string]$sha)
    $url = "https://api.github.com/repos/microsoft/netperf/dispatches"
    $body = @{
        event_type = "run-$type"
        client_payload = @{
            ref = $ref
            sha = $sha
            name = $name
        }
    } | ConvertTo-Json
    Write-Debug "POST $body to $url"
    Invoke-WebRequest -Uri $url -Method POST -Headers $headers -Body $body
}

function Get-Runs {
    param([string]$headers)
    $url = "https://api.github.com/repos/microsoft/netperf/actions/runs?event=repository_dispatch"
    Write-Debug "GET $url"
    return ((Invoke-WebRequest -Uri $url -Method GET -Headers $headers).Content | ConvertFrom-Json).workflow_runs
}

function Get-Run {
    param([string]$headers, [string]$runId)
    $url = "https://api.github.com/repos/microsoft/netperf/actions/runs/$runId"
    Write-Debug "GET $url"
    return (Invoke-WebRequest -Uri $url -Method GET -Headers $headers).Content | ConvertFrom-Json
}

function Get-Jobs {
    param([string]$headers, [string]$runId)
    $url = "https://api.github.com/repos/microsoft/netperf/actions/runs/$runId/jobs"
    Write-Debug "GET $url"
    return ((Invoke-WebRequest -Uri $url -Method GET -Headers $headers).Content | ConvertFrom-Json).jobs
}

function Get-RunId {
    param([string]$headers, [string]$name, [string]$sha)
    $workflows = Get-Runs $headers
    foreach ($workflow in $workflows) {
        $jobs = Get-Jobs $header $workflow.id
        foreach ($job in $jobs) {
            if ($job.name.Contains("$name-$sha")) {
                return $workflow.id
            }
        }
    }
    return $null
}

function Get-RunIdWithRetry {
    param([string]$headers, [string]$name, [string]$sha)
    $i = 0
    while ($i -lt 3) {
        $id = Get-RunId headers $name $sha
        if ($null -ne $id) {
            return $id
        }
        Write-Host "Run not found, retrying in 1 second..."
        Start-Sleep -Seconds 1
        $i++
    }
    Write-Error "Run not found!"
    return $null
}

function Get-RunStatus {
    param([string]$headers, [string]$id)
    $run = Get-Run $headers $id
    if ($run.status -ne "completed") {
        return $false
    }
    if ($run.conclusion -ne "success") {
        Write-Error "Run completed with status $($run.conclusion)!"
        return $true
    }
    Write-Host "Run succeeded!"
    return $true
}

function Wait-ForWorkflow {
    param([string]$headers, [string]$id)
    $i = 0
    while ($i -lt 120) { # 120 * 30 sec = 1 hour
        if (Get-RunStatus $headers $id) {
            return
        }
        Start-Sleep -Seconds 30
        $i++
    }
    Write-Error "Run timed out!"
}

# Get the workflow run id
Write-Host "Triggering new workflow..."
Start-Workflow $headers $name $ref $sha

# Get the workflow run id
Write-Host "Looking for workflow run..."
$id = Get-RunIdWithRetry $headers $name $sha
Write-Host "Workflow found: https://github.com/microsoft/netperf/actions/runs/$id"

# Wait for the run to complete
Write-Host "Waiting for run to complete..."
Wait-ForWorkflow $headers $id
