<#
.SYNOPSIS

    Reads an "azure-matrix.json" file and creates a pair of Azure VMs to use for testing foreach row in the matrix.

    Example usage:

        $password = '...'
        $token = '...'
        .\.github\workflows\create-azure-machines.ps1 -Password $password -GitHubToken $token
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$Password,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Experimental_Boost4", "Standard_DS2_v2", "Standard_F8s_v2")]
    [string]$VMSize = "Standard_F8s_v2", # TODO; once the Azure security team is done cluster migration, change this back.

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "netperf-ex",

    [Parameter(Mandatory = $false)]
    [string]$Location = "South Central US",

    [Parameter(Mandatory = $false)]
    [string]$GithubPatToken,

    [Parameter(Mandatory = $true)]
    [string]$WorkflowId
)

Set-StrictMode -Version "Latest"
$PSDefaultParameterValues["*:ErrorAction"] = "Stop"

$FoundAzureMatrix = Test-Path .\.github\workflows\azure-matrix.json
$FoundFullMatrix = Test-Path .\.github\workflows\processed-matrix.json

if (-not $FoundAzureMatrix -or -not $FoundFullMatrix) {
    Write-Host "Azure matrix or full matrix files not found."
    exit 0
}

$AzureMatrixJson = Get-Content -Path .\.github\workflows\azure-matrix.json | ConvertFrom-Json
$FullMatrixJson = Get-Content -Path .\.github\workflows\processed-matrix.json | ConvertFrom-Json

$jobs = @()
$RequiredPlatforms = New-Object 'System.Collections.Generic.HashSet[string]'

foreach ($entry in $AzureMatrixJson) {
    $IdTag = $entry.runner_id
    $Os = $entry.os
    $VMName1 = "$IdTag-1"
    $VMName2 = "$IdTag-2"
    Write-Host "[$(Get-Date)] Creating $VMName1 for platform $Os..."
    $jobs += Start-Job -ScriptBlock {
        & ./.github/workflows/create-azure-machine.ps1 `
            -VMName $Using:VMName1 `
            -Password $Using:Password `
            -Os $Using:Os `
            -VMSize $Using:VMSize `
            -ResourceGroupName $Using:ResourceGroupName `
            -Location $Using:Location `
            -WorkflowId $Using:WorkflowId
    }
    Write-Host "[$(Get-Date)] Creating $VMName2 for platform $Os..."
    $jobs += Start-Job -ScriptBlock {
        & ./.github/workflows/create-azure-machine.ps1 `
            -VMName $Using:VMName2 `
            -Password $Using:Password `
            -Os $Using:Os `
            -VMSize $Using:VMSize `
            -ResourceGroupName $Using:ResourceGroupName `
            -Location $Using:Location `
            -WorkflowId $Using:WorkflowId
    }

    $RequiredPlatforms.Add($Os) | Out-Null
}

$TimeoutMinutes = 12
$Timeout = $TimeoutMinutes * 60
$jobs | Wait-Job -Timeout $Timeout # Wait for all jobs to complete

# Stores the indicies of the VMs that were successfully created. We attempt to create 1 pair of VMs per row in AzureMatrixJson.
# Jobs assigned to VMs in a failed or running state (god knows what's going on with Azure) will be reassigned to healthy pairs of VMs.
$VMsSuccessfullyCreated = @()

# Stores the platforms that were successfully covered by the VMs created.
$PlatformsCovered = New-Object 'System.Collections.Generic.HashSet[string]'
for ($i = 0; $i -lt $jobs.Count; $i += 2) {

    $VM1_Job_Status = $jobs[$i].State
    $VM2_Job_Status = $jobs[$i + 1].State

    if ($VM1_Job_Status -eq "Completed" -and $VM2_Job_Status -eq "Completed") {
        $VMsSuccessfullyCreated += ($i / 2)
        $PlatformsCovered.Add($AzureMatrixJson[$i / 2].os) | Out-Null
    } else {
        Write-Host "[$(Get-Date)] VM creation failed for $($AzureMatrixJson[$i / 2].runner_id)"
    }
}

Write-Host "`n[$(Get-Date)] Jobs complete!`n"
$jobs | Remove-Job -Force  # Clean up all the jobs
if ($RequiredPlatforms.Count -ne $PlatformsCovered.Count) {
    Write-Error "Failed to create enough VMs."
    exit 1
}

function Get-NetPerfVmPrivateIp {
    param ($VMName)
    $nic = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name "$VMName-Nic"
    return $nic.IpConfigurations[0].PrivateIpAddress
}

if ($GithubPatToken) {

    # Define the header with the authorization token
    $headers = @{
        "Authorization" = "token $GithubPatToken"
    }

    # Make the POST request and store the response
    $response = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/netperf/actions/runners/registration-token" -Method Post -Headers $headers

    # Output the token
    $GitHubRegistrationToken = $response.token

    $jobs = @()
    foreach ($index in $VMsSuccessfullyCreated) {
        # Only configure the pairs of VMs successfully provisioned.
        $entry = $AzureMatrixJson[$index]
        $Os = $entry.os
        $RunnerId = $entry.runner_id
        $VMName1 = "$($entry.runner_id)-1"
        $VMName2 = "$($entry.runner_id)-2"
        $osType = $Os.Split("-")[0]
        $ip1 = Get-NetPerfVmPrivateIp $VMName1
        $ip2 = Get-NetPerfVmPrivateIp $VMName2

        if ($osType -eq "windows") {
            Write-Host "[$(Get-Date)] Configuring GitHub peer machine"
            $jobs += Start-Job -ScriptBlock {
                $scriptParams = @{
                    "Username" = "netperf"
                    "Password" = $Using:Password
                    "PeerIP" = $Using:ip1
                }
                Invoke-AzVMRunCommand `
                    -ResourceGroupName $Using:ResourceGroupName `
                    -VMName $Using:vmName2 `
                    -CommandId "RunPowerShellScript" `
                    -ScriptPath ".\setup-runner-windows.ps1" `
                    -Parameter $scriptParams `
                    -Verbose

                Write-Host "[$(Get-Date)] Restarting peer machine"
                Restart-AzVM -ResourceGroupName $Using:ResourceGroupName -Name $Using:vmName2
            }

            Write-Host "[$(Get-Date)] Configuring GitHub runner machine"
            $jobs += Start-Job -ScriptBlock {
                $scriptParams = @{
                    "Username" = "netperf"
                    "Password" = $Using:Password
                    "PeerIP" = $Using:ip2
                    "GitHubToken" = $Using:GitHubRegistrationToken
                    "RunnerLabels" = "os-$Using:Os,$Using:RunnerId,x64"
                }
                Invoke-AzVMRunCommand `
                    -ResourceGroupName $Using:ResourceGroupName `
                    -VMName $Using:VMName1 `
                    -CommandId "RunPowerShellScript" `
                    -ScriptPath ".\setup-runner-windows.ps1" `
                    -Parameter $scriptParams `
                    -Verbose

                Write-Host "[$(Get-Date)] Restarting GitHub runner machine"
                Restart-AzVM -ResourceGroupName $Using:ResourceGroupName -Name $Using:VMName1
            }
        } else {
            Write-Host "[$(Get-Date)] Configuring Linux GitHub peer machine"
            $jobs += Start-Job -ScriptBlock {
                $scriptParams = @{
                    "username" = "netperf"
                    "password" = $Using:Password
                    "peerip" = $Using:ip1
                    "noreboot" = $true
                }
                Invoke-AzVMRunCommand `
                    -ResourceGroupName $Using:ResourceGroupName `
                    -VMName $Using:VMName2 `
                    -CommandId "RunShellScript" `
                    -ScriptPath ".\setup-runner-linux.sh" `
                    -Parameter $scriptParams

                Write-Host "[$(Get-Date)] Restarting peer machine"
                Restart-AzVM -ResourceGroupName $Using:ResourceGroupName -Name $Using:VMName2
            }

            Write-Host "[$(Get-Date)] Configuring Linux GitHub runner machine"
            $jobs += Start-Job -ScriptBlock {
                $scriptParams = @{
                    "username" = "netperf"
                    "password" = $Using:Password
                    "peerip" = $Using:ip2
                    "githubtoken" = $Using:GitHubRegistrationToken
                    "noreboot" = $true
                    "runnerlabels" = "os-$Using:Os,$Using:RunnerId"
                }
                Invoke-AzVMRunCommand `
                    -ResourceGroupName $Using:ResourceGroupName `
                    -VMName $Using:VMName1 `
                    -CommandId "RunShellScript" `
                    -ScriptPath ".\setup-runner-linux.sh" `
                    -Parameter $scriptParams

                Write-Host "[$(Get-Date)] Restarting GitHub runner machine"
                Restart-AzVM -ResourceGroupName $Using:ResourceGroupName -Name $Using:VMName1
            }
        }
    }

    $jobs | Wait-Job    # Wait for all jobs to complete
    Write-Host "`n[$(Get-Date)] Jobs complete!`n"
    $jobs | Receive-Job # Get job results
    $jobs | Remove-Job  # Clean up the jobs
}

# In case of any setup failure, we filter down our list of successfully created VMs to just the ones able to be successfully onboarded to GitHub.
$SuccessfulVmsOnboardedToGitHub = @()
$PlatformsSuccessfullyOnboardedToGitHub = New-Object 'System.Collections.Generic.HashSet[string]'
$headers = @{
    Authorization = "token $GithubPatToken"
    Accept = "application/vnd.github+json"
}
# GitHub API URL to list runners
$RunnersUrl = "https://api.github.com/repos/microsoft/netperf/actions/runners"
# Fetch the list of runners from GitHub
$Runners = Invoke-RestMethod -Uri $RunnersUrl -Method Get -Headers $headers
foreach ($index in $VMsSuccessfullyCreated) {
    $entry = $AzureMatrixJson[$index]
    $RunnerId = $entry.runner_id
    foreach ($runner in $Runners.runners) {
        if ($runner.name.Contains($RunnerId)) {
            $SuccessfulVmsOnboardedToGitHub += $index
            $PlatformsSuccessfullyOnboardedToGitHub.Add($entry.os) | Out-Null
            Write-Host "[$(Get-Date)] Successfully onboarded $RunnerId to GitHub!"
            break
        }
    }
}
if ($PlatformsSuccessfullyOnboardedToGitHub.Count -ne $RequiredPlatforms.Count) {
    Write-Error "Failed to onboard successfully created VMs to GitHub for the required platforms"
    exit 1
}

# Now we should reassign the tags for jobs missing a successfully provisioned VM onboarded to Github.
$SuccessfulPairs = @{} # Stores the 'runner_id' tags for the VMs that were successfully provisioned.
foreach ($index in $SuccessfulVmsOnboardedToGitHub) {
    $entry = $AzureMatrixJson[$index]
    $SuccessfulPairs[$entry.runner_id] = $entry.os
}

$RoundRobinCandidates = @($SuccessfulPairs.Keys)
$RoundRobinIndex = 0
foreach ($entry in $AzureMatrixJson) {
    if ($SuccessfulPairs.ContainsKey($entry.runner_id)) {
        # This pair was successfully provisioned.
        continue
    }
    $MissingTag = $entry.runner_id
    $RequiredOs = $entry.os
    # In a round-robin style, reassign this job's tag to one of the successpair's tag that matches the required OS.
    while ($true) {
        $ReplacementTag = $RoundRobinCandidates[$RoundRobinIndex]
        $ReplacementOs = $SuccessfulPairs[$ReplacementTag]
        if ($ReplacementOs -eq $RequiredOs) {
            Write-Host "[$(Get-Date)] Reassigning $MissingTag to $ReplacementTag"
            $entry.runner_id = $ReplacementTag
            foreach ($row in $FullMatrixJson) {
                $propertyToCheck = "runner_id"
                $propertyExists = $row | Get-Member -MemberType NoteProperty -Name $propertyToCheck
                if ($propertyExists -eq $null) {
                    continue
                }
                if ($row.runner_id -eq $MissingTag) {
                    $row.runner_id = $ReplacementTag
                }
            }
            $RoundRobinIndex = ($RoundRobinIndex + 1) % $RoundRobinCandidates.Count
            break
        }
        $RoundRobinIndex = ($RoundRobinIndex + 1) % $RoundRobinCandidates.Count
    }
}

$FullMatrixJson | ConvertTo-Json | Set-Content -Path .\.github\workflows\processed-matrix.json
$AzureMatrixJson | ConvertTo-Json | Set-Content -Path .\.github\workflows\azure-matrix.json
Write-Host "`n[$(Get-Date)] Matrix updated!`n"
