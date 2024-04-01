<#
.SYNOPSIS
    Removes an Azure VMs created by create-azure-machines.ps1.
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$VMName,

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "netperf-ex"
)

Set-StrictMode -Version "Latest"
$PSDefaultParameterValues["*:ErrorAction"] = "Stop"

Write-Host "$vmName`: Removing VM"
try {
    $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $vmName
    $null = $vm | Remove-AzVM -Force
} catch {
    Write-Host "$vmName`: No VM found"
}

Write-Host "$vmName`: Removing Public IP"
try {
    Remove-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name "$vmName-PublicIP" -Force
} catch {
    Write-Host "$vmName`: No Public IP found"
}

Write-Host "$vmName`: Removing NSG"
try {
    Remove-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Name "$vmName-Nsg" -Force
} catch {
    Write-Host "$vmName`: No NSG found"
}

Write-Host "$vmName`: Removing OS Disk"
try {
    $osDisk = $vm.StorageProfile.OSDisk
    Remove-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $osDisk.Name -Force
} catch {
    Write-Host "$vmName`: No OS Disk found"
}
