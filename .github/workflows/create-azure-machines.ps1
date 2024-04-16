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
    [ValidateSet("windows-2025", "windows-2022", "windows-2019", "ubuntu-22.04", "ubuntu-20.04", "ubuntu-18.04", "mariner-2")]
    [string]$Os = "windows-2022",

    [Parameter(Mandatory = $false)]
    [ValidateSet("Experimental_Boost4", "Standard_DS2_v2", "Standard_F8s_v2")]
    [string]$VMSize = "Experimental_Boost4",

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "netperf-ex",

    [Parameter(Mandatory = $false)]
    [string]$Location = "South Central US",

    [Parameter(Mandatory = $false)]
    [string]$EnvTag = "azure-ex",

    [Parameter(Mandatory = $false)]
    [string]$GitHubToken,

    [Parameter(Mandatory = $true)]
    [string]$WorkflowId
)

Set-StrictMode -Version "Latest"
$PSDefaultParameterValues["*:ErrorAction"] = "Stop"

$osType = $Os.Split("-")[0]

$jobs = @()
Write-Host "[$(Get-Date)] Creating $VMName1..."
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
Write-Host "[$(Get-Date)] Creating $VMName2..."
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
$jobs | Wait-Job    # Wait for all jobs to complete
Write-Host "`n[$(Get-Date)] Jobs complete!`n"
$jobs | Receive-Job # Get job results
$jobs | Remove-Job  # Clean up the jobs

function Get-NetPerfVmPrivateIp {
    param ($VMName)
    $nic = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name "$VMName-Nic"
    return $nic.IpConfigurations[0].PrivateIpAddress
}

if ($GitHubToken) {

    $ip1 = Get-NetPerfVmPrivateIp $VMName1
    $ip2 = Get-NetPerfVmPrivateIp $VMName2

    $jobs = @()

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

    $jobs | Wait-Job    # Wait for all jobs to complete
    Write-Host "`n[$(Get-Date)] Jobs complete!`n"
    $jobs | Receive-Job # Get job results
    $jobs | Remove-Job  # Clean up the jobs
}
