<#
.SYNOPSIS
    TODO:
        Abstract Pool Queue -
        Since we have only have 150 VMs, we need a way to queue outstanding workflows and resolve concurrent workflow race conditions.
        A naive idea is to check the list of VMs in azure, and if there are not enough VMs to accomodate this workflow run, we wait and opportunistically delete dead VMs in a loop.
        However, If multiple workflows try to create VMs simultaneously, we run into a race condition where all workflows initially think there is enough VMs.
        When all workflows try and create the VMs, some of them fail because of resource exhaustion. We need a way to queue the workflow runs themselves.
        One idea is to leverage the Github API to check all running workflows, and only allow the oldest workflows to run and the rest should wait if there are not enough resources for all runs.

    Logic:

    1. Opportunistically deletes dead Azure VMs. We consider a VM dead if it has a "workflow ID" tag, but there is currently no 'in_progress' workflow with that ID.

    2. Determines how many Azure VMs we will create based on ./matrix.json, and modifies ./matrix.json to reflect the tags of the VMs we will create.

    TODO: 3. Query Github API (in a loop) to check all running workflows while querying for existing Azure VMs (deleting them if they are dead).
            If there are not enough VMs for all concurrent runs + existing alive VMs, block the newer runs and only allow the older created runs to unblock (within resource cap).
            Repeat loop until this run gets unblocked.
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$GithubPatToken,

    [Parameter(Mandatory = $false)]
    [string]$MatrixFileName = "quic_matrix.json",

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "netperf-ex",

    [Parameter(Mandatory = $false)]
    [string]$ThisWorkflowId = "NULL"
)

function Remove-GitHubRunner {
    param (
        $Tag,
        $runners,
        $headers
    )
    # GitHub API URL to list runners
    $apiUrl = "https://api.github.com/repos/microsoft/netperf/actions/runners"

    try {
        # Fetch the list of runners from GitHub
        $runners = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers

        # Filter for the runner with the specified tag
        $runner = $runners.runners | Where-Object { $_.labels.name -contains $Tag }

        if ($runner) {
            # If runner is found, prepare to remove it
            $deleteUrl = "$apiUrl/$($runner.id)"

            # Send DELETE request to remove the runner
            Invoke-RestMethod -Uri $deleteUrl -Method Delete -Headers $headers
            Write-Output "Runner with ID $($runner.id) and tag '$Tag' has been removed."
        }
        else {
            Write-Output "No runner found with tag '$Tag'."
        }
    }
    catch {
        Write-Error "Failed to query or remove the runner: $_"
    }
}

Set-StrictMode -Version "Latest"
$PSDefaultParameterValues["*:ErrorAction"] = "Stop"

$MatrixJson = Get-Content -Path .\.github\workflows\$MatrixFileName | ConvertFrom-Json
$NumVms = $MatrixJson.Count * 2 # We need two VMs per matrix entry for pair machine tests.
$vms = Get-AzVM -ResourceGroupName $ResourceGroupName
$jobs = @()

# 1. In case previous jobs failed to cleanup their VMs, we opportunistically delete them here.
try {

    $headers = @{
        Authorization = "token $GithubPatToken"
        Accept = "application/vnd.github+json"
    }

    # GitHub API URL to list runners
    $RunnersUrl = "https://api.github.com/repos/microsoft/netperf/actions/runners"
    # GitHub API to list workflow runs
    $WorkflowRunsUrl = "https://api.github.com/repos/microsoft/netperf/actions/runs"

    # Fetch the list of runners from GitHub
    $Runners = Invoke-RestMethod -Uri $RunnersUrl -Method Get -Headers $headers
    # Fetch the list of workflow runs from GitHub
    $WorkflowRuns = Invoke-RestMethod -Uri $WorkflowRunsUrl -Method Get -Headers $headers

    $tagsRemoved =[System.Collections.Generic.List[string]]::new()
    $aliveVm =[System.Collections.Generic.List[string]]::new()

    $vms | Foreach-Object {
        $vm = $_
        $vmCreationTime = $vm.Tags["CreationTime"]
        $vmWorkflowId = $vm.Tags["WorkflowId"]
        if (!($vm.Name.Contains("ex-")) -or !($vm.Name.Contains("f4-")) -or !($vm.Name.Contains("f8-"))) {

            $WorkflowThatReferenceThisVm = $WorkflowRuns.workflow_runs | Where-Object {
                $_.workflow_id -eq $vmWorkflowId -and $_.status -eq 'in_progress'
            }

            if ($WorkflowThatReferenceThisVm -and !($vmWorkflowId -eq $ThisWorkflowId)) {
                Write-Host "Ignoring VM: $($vm.Name) as it's in use by a running workflow. Workflow ID: $vmWorkflowId, Vm Creation Time: $vmCreationTime"
                $aliveVm.Add($vm.Name)
                continue
            }

            $name = $vm.Name
            if ($name.EndsWith("1")) {
                Write-Host "Removing Github Self Hosted Runner with Tag: $($vm.Name)..."
                $tagToRemove = $name.Substring(0, $name.Length - 2)
                $tagsRemoved.Add($tagToRemove)
                Remove-GitHubRunner -Tag $tagToRemove -runners $Runners -headers $headers
            }
            Write-Host "Deleting VM: $($vm.Name)..."
            $jobs += Start-Job -ScriptBlock {
                & ./.github/workflows/remove-azure-machine.ps1 -VMName $Using:name
            }
        } else {
            Write-Host "Ignoring VM: $($vm.Name) as it's not a temporary VM."
        }
    }

    if ($jobs.Count -gt 0) {
        Write-Host "`n[$(Get-Date)] Deleting residual dead VMs...`n"
        Wait-Job -Job $jobs
        Write-Host "`n[$(Get-Date)] Residual Dead VMs deleted!`n"
        $jobs | Receive-Job # Get job results
        $jobs | Remove-Job  # Clean up the jobs
    }

    # Cleaning up any residual temporary self hosted runners
    $Runners.runners | Foreach-Object {
        $runner = $_
        $runnerName = $runner.name
        if (!($runnerName.Contains("ex-")) -and !($tagsRemoved.Contains($runnerName)) -and !($aliveVm.Contains($runnerName)) -and $runnerName.EndsWith("-1")) {
            Write-Host "Cleaning up Residual Github Self Hosted Runner with Tag: $runnerName..."
            $tagToRemove = $runnerName.Substring(0, $runnerName.Length - 2)
            Remove-GitHubRunner -Tag $tagToRemove -runners $Runners -headers $headers
        }
    }

} catch {
    Write-Host "Error managing VMs. Full error: $_"
}

$AzureJson = @()
$ProcessedJson = @()

# 2. Modify matrix.json.
foreach ($entry in $MatrixJson) {

    if ($entry.env -match "azure") {
        # TODO: Remove this once Security has been sorted out.
        continue
    }

    # check if entry.env has substring "azure" in it
    if ($entry.env -match "azure" -and $entry.os -match "windows-2022") {
        $randomTag = [System.Guid]::NewGuid().ToString()
        # limit randomTag to 13 characters
        $randomTag = $randomTag.Substring(0, [Math]::Min(12, $randomTag.Length))
        $randomTag = "a" + $randomTag
        $entry | Add-Member -MemberType NoteProperty -Name "runner_id" -Value $randomTag
        $AzureJson += $entry
        $ProcessedJson += $entry
    } elseif ($entry.env -match "azure" -and $entry.os -match "ubuntu-24.04") {
        continue
    } else {
        $ProcessedJson += $entry
    }
}

# Save JSON to file
$ProcessedJson | ConvertTo-Json | Set-Content -Path .\.github\workflows\processed-matrix.json
$AzureJson | ConvertTo-Json | Set-Content -Path .\.github\workflows\azure-matrix.json

# 3. TODO; load management with Abstract Pool Queue Logic here.
