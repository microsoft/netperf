param (
    [Parameter(Mandatory = $true)]
    [string]$pat,

    [Parameter(Mandatory = $true)]
    [string]$name,

    [Parameter(Mandatory = $true)]
    [string]$ref,

    [Parameter(Mandatory = $true)]
    [string]$sha
)

Set-StrictMode -Version 'Latest'
$PSDefaultParameterValues['*:ErrorAction'] = 'Stop'

function Start-Workflow {
    param([string]$pat, [string]$name, [string]$ref, [string]$sha)
    $Headers = @{
        "Accept" = "application/vnd.github+json"
        "Authorization" = "Bearer $pat"
        "X-GitHub-Api-Version" = "2022-11-28"
    }
    $body = @{
        event_type = "run-quic"
        client_payload = @{
            ref = $ref
            sha = $sha
            name = $name
        }
    } | ConvertTo-Json
    Invoke-WebRequest -Uri "https://api.github.com/repos/microsoft/netperf/dispatches" -Method POST -Headers $Headers -Body $body
}

function Get-WorkflowRunId {
    param([string]$name, [string]$sha)
    $results =
      gh run list -R microsoft/netperf -e repository_dispatch `
        | Select-String -Pattern 'repository_dispatch\s+(\d+)' -AllMatches ` # TODO - Limit to top N
        | Foreach-Object { $_.Matches } `
        | Foreach-Object { $_.Groups[1].Value }
    foreach ($result in $results) {
      if (gh run view -R microsoft/netperf $result | Select-String -Pattern "$name-$sha") {
          return $result
      }
    }
    return $null
}

function Get-WorkflowRunIdWithRetry {
    param([string]$name, [string]$sha)
    $i = 0
    while ($i -lt 3) {
        $id = Get-WorkflowRunId $name $sha
        if ($null -ne $id) {
            return $id
        }
        Write-Host "Workflow not found, retrying in 1 second..."
        Start-Sleep -Seconds 1
        $i++
    }
    Write-Error "Workflow not found!"
    return $null
}

function Get-WorkflowStatus {
    param([string]$id)
    $output = gh run view -R microsoft/netperf $id --exit-status
    if ($LastExitCode) {
        Write-Error "Workflow failed!"
        return $true
    }
    if ($output | Select-String -Pattern "X Complete") {
        Write-Error "Workflow failed!"
        return $true
    }
    if (($output | Select-String -Pattern "Γ£ô Complete") -or ($output | Select-String -Pattern "✓ Complete")) {
        Write-Host "Workflow succeeded!"
        return $true
    }
    return $false
}

function Wait-ForWorkflow {
    param([string]$id)
    $i = 0
    while ($i -lt 120) { # 120 * 30 sec = 1 hour
        if (Get-WorkflowStatus $id) {
            return
        }
        Start-Sleep -Seconds 30
        $i++
    }
    Write-Error "Workflow timed out!"
}

# Get the workflow run id
Write-Host "Triggering new workflow..."
Start-Workflow

# Get the workflow run id
Write-Host "Looking for workflow run..."
$id = Get-WorkflowRunIdWithRetry $name $sha
Write-Host "Workflow found: https://github.com/microsoft/netperf/actions/runs/$id"

# Wait for the workflow to complete
Write-Host "Waiting for workflow to complete..."
Wait-ForWorkflow $id
