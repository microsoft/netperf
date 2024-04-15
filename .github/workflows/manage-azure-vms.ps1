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

    1. Opportunistically deletes dead Azure VMs. We consider a VM dead if it's creation time is more than 30 minutes ago, as we have a 20 minute time-out per job.
       A VM is also dead if it has a "workflow ID" tag, but there is currently no running workflow with that ID.

    2. Determines how many Azure VMs we will create based on ./matrix.json, and modifies ./matrix.json to reflect the tags of the VMs we will create.

    TODO: 3. Query Github API (in a loop) to check all running workflows while querying for existing Azure VMs (deleting them if they are dead).
            If there are not enough VMs for all concurrent runs + existing alive VMs, block the newer runs and only allow the older created runs to unblock (within resource cap).
            Repeat loop until this run gets unblocked.
#>

Set-StrictMode -Version "Latest"
$PSDefaultParameterValues["*:ErrorAction"] = "Stop"

$ResourceGroupName = "netperf-ex"
$MatrixJson = Get-Content -Path .\.github\workflows\matrix.json | ConvertFrom-Json
$NumVms = $MatrixJson.Count * 2 # We need two VMs per matrix entry for pair machine tests.
$vms = Get-AzVM -ResourceGroupName $ResourceGroupName
$jobs = @()

# 1. In case previous jobs failed to cleanup their VMs, we opportunistically delete them here.
try {
    $vms | Foreach-Object {
    $vm = $_
    $vmCreationTime = $vm.Tags["CreationTime"]
    $vmWorkflowId = $vm.Tags["WorkflowId"]
    if ($vmCreationTime -or !($vm.Name.Contains("ex-"))) {
        # $vmCreationTime = [DateTime]::Parse($vmCreationTime)
        # $timeSinceCreation = (Get-Date) - $vmCreationTime
        # if ($timeSinceCreation.TotalMinutes -gt 30) {
        #     Write-Host "VM: $($vm.Name) is dead. Deleting..."
        #     $jobs += Start-Job -ScriptBlock {
        #         & ./.github/workflows/remove-azure-machine.ps1 -VMName $vm.Name
        #     }
        # } else {
        #     Write-Host "VM: $($vm.Name) is alive. Ignoring."
        # }
        Write-Host "Deleting VM: $($vm.Name)..."
        $jobs += Start-Job -ScriptBlock {
            & ./.github/workflows/remove-azure-machine.ps1 -VMName $vm.Name
        }
    } else {
        Write-Host "Ignoring VM: $($vm.Name) as it's not a temporary VM."
    }
        # TODO: leverage Github API and do something with $vmWorkflowId.
    }
    if ($jobs.Count -gt 0) {
        Write-Host "`n[$(Get-Date)] Deleting residual dead VMs...`n"
        Wait-Job -Job $jobs
        Write-Host "`n[$(Get-Date)] Residual Dead VMs deleted!`n"
        $jobs | Receive-Job # Get job results
        $jobs | Remove-Job  # Clean up the jobs
    }
} catch {
    Write-Host "Likely some other job is already cleaning up the VMs. Full error: $_"
}

$AzureJson = @()
# 2. Modify matrix.json.
foreach ($entry in $MatrixJson) {
    # check if entry.env has substring "azure" in it
    if ($entry.env -match "azure" -and $entry.os -match "windows-2022") { # TODO: Add support for windows-2025 and Linux.
        $randomTag = [System.Guid]::NewGuid().ToString()
        # limit randomTag to 13 characters
        $randomTag = $randomTag.Substring(0, [Math]::Min(13, $randomTag.Length))
        $entry.env = $randomTag
        $AzureJson += $entry
    }
}

# Save JSON to file
$MatrixJson | ConvertTo-Json | Set-Content -Path .\.github\workflows\processed-matrix.json
$AzureJson | ConvertTo-Json | Set-Content -Path .\.github\workflows\azure-matrix.json

# 3. TODO
