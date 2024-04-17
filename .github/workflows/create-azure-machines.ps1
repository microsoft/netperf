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
    [string]$VMSize = "Experimental_Boost4",

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "netperf-ex",

    [Parameter(Mandatory = $false)]
    [string]$Location = "South Central US",

    [Parameter(Mandatory = $false)]
    [string]$GitHubToken,

    [Parameter(Mandatory = $true)]
    [string]$WorkflowId
)

Set-StrictMode -Version "Latest"
$PSDefaultParameterValues["*:ErrorAction"] = "Stop"

$AzureMatrixJson = Get-Content -Path .\.github\workflows\azure-matrix.json | ConvertFrom-Json
$FullMatrixJson = Get-Content -Path .\.github\workflows\processed-matrix.json | ConvertFrom-Json

$jobs = @()
$RequiredPlatforms = New-Object 'System.Collections.Generic.HashSet[string]'

foreach ($entry in $AzureMatrixJson) {
    $IdTag = $entry.env
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
        Write-Host "[$(Get-Date)] VM creation failed for $($AzureMatrixJson[$i / 2].env)"
    }
}

Write-Host "`n[$(Get-Date)] Jobs complete!`n"
$jobs | Receive-Job # Get job results
$jobs | Remove-Job -Force  # Clean up all the jobs
if ($RequiredPlatforms.Count -ne $PlatformsCovered.Count) {
    $MissingPlatforms = $RequiredPlatforms - $PlatformsCovered
    Write-Error "Failed to create VMs for the following platforms: $MissingPlatforms"
    exit 1
}

function Get-NetPerfVmPrivateIp {
    param ($VMName)
    $nic = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name "$VMName-Nic"
    return $nic.IpConfigurations[0].PrivateIpAddress
}

if ($GitHubToken) {
    $jobs = @()
    foreach ($index in $VMsSuccessfullyCreated) {
        # Only configure the pairs of VMs successfully provisioned.
        $entry = $AzureMatrixJson[$index]
        $Os = $entry.os
        $EnvTag = $entry.env
        $VMName1 = "$($entry.env)-1"
        $VMName2 = "$($entry.env)-2"
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
                    "GitHubToken" = $Using:GitHubToken
                    "RunnerLabels" = "os-$Using:Os,$Using:EnvTag,x64"
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
                    "githubtoken" = $Using:GitHubToken
                    "noreboot" = $true
                    "runnerlabels" = "os-$Using:Os,$Using:EnvTag"
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

# Now we should reassign the tags for jobs missing a successfully provisioned VM.

# Stores the 'env' tags for the VMs that were successfully provisioned.
$SuccessfulPairs = @{}
foreach ($index in $VMsSuccessfullyCreated) {
    $entry = $AzureMatrixJson[$index]
    $SuccessfulPairs[$entry.env] = $entry.os
}

$RoundRobinCandidates = @($SuccessfulPairs.Keys)
$RoundRobinIndex = 0
foreach ($entry in $AzureMatrixJson) {
    if ($SuccessfulPairs.ContainsKey($entry.env)) {
        # This pair was successfully provisioned.
        continue
    }
    $MissingTag = $entry.env
    $RequiredOs = $entry.os
    # In a round-robin style, reassign this job's tag to one of the successpair's tag that matches the required OS.
    while ($true) {
        $ReplacementTag = $RoundRobinCandidates[$RoundRobinIndex]
        $ReplacementOs = $SuccessfulPairs[$ReplacementTag]
        if ($ReplacementOs -eq $RequiredOs) {
            Write-Host "[$(Get-Date)] Reassigning $MissingTag to $ReplacementTag"
            $entry.env = $ReplacementTag
            foreach ($row in $FullMatrixJson) {
                if ($row.env -eq $MissingTag) {
                    $row.env = $ReplacementTag
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
