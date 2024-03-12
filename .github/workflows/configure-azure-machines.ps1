<#
.SYNOPSIS
    Configures a pair of existing Azure VMs for testing.
#>

param (
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "netperf-ex",

    [Parameter(Mandatory = $false)]
    [string]$Location = "South Central US",

    [Parameter(Mandatory = $false)]
    [string]$EnvTag = "azure-ex",

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$GitHubToken,

    [Parameter(Mandatory = $true)]
    [string]$Password,

    [Parameter(Mandatory = $true)]
    [string]$VMSuffix1,

    [Parameter(Mandatory = $true)]
    [string]$VMSuffix2,
)

if ($SubscriptionId) {
    # Connect to Azure, otherwise assume we're already connected.
    Connect-AzAccount -SubscriptionId $subscriptionId
}

$vmName1 = "ex-$osType-$VMSuffix1"
$vmName2 = "ex-$osType-$VMSuffix2"

function Get-NetPerfVmPrivateIp {
    param ($vmName)
    $nic = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name "$vmName-Nic"
    return $nic.IpConfigurations[0].PrivateIpAddress
}

if ($GitHubToken) {

    $ip1 = Get-NetPerfVmPrivateIp $vmName1
    $ip2 = Get-NetPerfVmPrivateIp $vmName2

    if ($osType -eq "windows") {
        Write-Host "Configuring GitHub peer machine"
        $scriptParams = @{
            "Username" = $username
            "Password" = $securePassword
            "PeerIP" = $ip1
        }
        Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $vmName2 -CommandId "RunPowerShellScript" -ScriptPath ".\setup-runner-windows.ps1" -Parameter $scriptParams

        Write-Host "Restarting peer machine"
        Restart-AzVM -ResourceGroupName $ResourceGroupName -Name $vmName2

        Write-Host "Configuring GitHub runner machine"
        $scriptParams = @{
            "Username" = $username
            "Password" = $securePassword
            "PeerIP" = $ip2
            "GitHubToken" = $GitHubToken
            "RunnerLabels" = "os-$Os,$EnvTag"
        }
        Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $vmName1 -CommandId "RunPowerShellScript" -ScriptPath ".\setup-runner-windows.ps1" -Parameter $scriptParams

        Write-Host "Restarting GitHub runner machine"
        Restart-AzVM -ResourceGroupName $ResourceGroupName -Name $vmName1
    } else {
        Write-Host "Configuring Linux GitHub peer machine"
        $scriptParams = @{
            "username" = $username
            "password" = $securePassword
            "peerip" = $ip1
            "noreboot" = $true
        }
        Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $vmName2 -CommandId "RunShellScript" -ScriptPath ".\setup-runner-linux.sh" -Parameter $scriptParams

        Write-Host "Configuring Linux GitHub runner machine"
        $scriptParams = @{
            "username" = $username
            "password" = $securePassword
            "peerip" = $ip2
            "githubtoken" = $GitHubToken
            "noreboot" = $true
            "runnerlabels" = "os-$Os,$EnvTag"
        }
        Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $vmName1 -CommandId "RunShellScript" -ScriptPath ".\setup-runner-linux.sh" -Parameter $scriptParams
    }
}
