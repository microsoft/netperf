<#
.SYNOPSIS
    Creates an Azure VMs to use for testing with netperf.
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$VMName,

    [Parameter(Mandatory = $true)]
    [string]$Password,

    [Parameter(Mandatory = $false)]
    [ValidateSet("windows-2025", "windows-2022", "windows-2019", "ubuntu-22.04", "ubuntu-24.04", "ubuntu-18.04", "mariner-2")]
    [string]$Os = "windows-2022",

    [Parameter(Mandatory = $false)]
    [ValidateSet("Experimental_Boost4", "Standard_DS2_v2", "Standard_F8s_v2")]
    [string]$VMSize = "Standard_F8s_v2", # TODO; once the Azure security team is done cluster migration, change this back.

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "netperf-ex",

    [Parameter(Mandatory = $false)]
    [string]$Location = "South Central US",

    [Parameter(Mandatory = $false)]
    [switch]$NoPublicIP = $false,

    [Parameter(Mandatory = $true)]
    [string]$WorkflowId
)

Set-StrictMode -Version "Latest"
$PSDefaultParameterValues["*:ErrorAction"] = "Stop"

$osType = $Os.Split("-")[0]
$imageByParts = $true
if ($Os -eq "windows-2025") {
    $subscriptionId = "DDITIMAGEFACTORY-PUBLIC"
    $resourceGroupName = "DEVDIVIMAGEGALLERY"
    $galleryName = "DevDivImageGallery"
    $imageName = "ge_release-edition_server_serverdatacentercore_en-us_vl"
    $versionId = "latest"
    $image = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Compute/galleries/$galleryName/images/$imageName/versions/$versionId"
    $imageByParts = $false
} elseif ($Os -eq "windows-2022") {
    $image = "MicrosoftWindowsServer:WindowsServer:2022-datacenter-g2:latest"
} elseif ($Os -eq "windows-2019") {
    $image = "MicrosoftWindowsServer:WindowsServer:2019-datacenter-gensecond:17763.5576.240304"
} elseif ($Os -eq "ubuntu-22.04") {
    $image = "Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:22.04.202403010"
} elseif ($Os -eq "ubuntu-24.04") {
    $image = " Canonical:ubuntu-24_04-lts:server:latest"
} elseif ($Os -eq "mariner-2") {
    $image = "MicrosoftCBLMariner:cbl-mariner:cbl-mariner-2-gen2:2.20240223.01" # This image may not exist
} else {
    Write-Error "Unknown OS: $Os"
}
$username = "netperf"
$securePassword = $Password | ConvertTo-SecureString -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ($username, $securePassword)

try {
    Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName | Out-Null
    Write-Host "`nFound $VMName already created. Skipping..."
    return
} catch { }

Write-Host "[$(Get-Date)] Creating $VMName ($os, $VMSize, $ResourceGroupName, $Location)"

try {
    Get-AzResourceGroup -Name $ResourceGroupName | Out-Null
    Write-Host "[$(Get-Date)] Found resource group"
} catch {
    Write-Host "[$(Get-Date)] Error getting resource group: $_. Will try and create a new one..."
    New-AzResourceGroup -Name $ResourceGroupName -Location $Location | Out-Null
    Write-Host "[$(Get-Date)] Created resource group"
}

$vnetName = "exvnet"
try {
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $vnetName
    Write-Host "[$(Get-Date)] Found vnet"
} catch {
    Write-Host "[$(Get-Date)] Error getting vnet: $_. Will try and create a new one..."
    $vnet = New-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $vnetName -Location $Location -AddressPrefix "10.0.0.0/16"
    Write-Host "[$(Get-Date)] Created vnet"
}

$subnetName = "exsubnet"
try {
    $subnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $subnetName
    Write-Host "[$(Get-Date)] Found subnet config"
} catch {
    Write-Host "[$(Get-Date)] Error getting subnet config: $_. Will try and create a new one..."
    $subnet = Add-AzVirtualNetworkSubnetConfig -Name $subnetName -VirtualNetwork $vnet -AddressPrefix "10.0.1.0/24"
    $vnet | Set-AzVirtualNetwork | Out-Null
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $vnetName
    $subnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $subnetName
    Write-Host "[$(Get-Date)] Created subnet config"
}

$storageName = "exbootstorage2"
try {
    $storage = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $storageName
    Write-Host "[$(Get-Date)] Found storage account"
} catch {
    Write-Host "[$(Get-Date)] Error getting storage account: $_. Will try and create a new one..."
    $storage = New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $storageName -Location $Location -SkuName "Standard_LRS"
    Write-Host "[$(Get-Date)] Created storage account"
}

#$proximity = "exproximity"
#try {
#    $proximity = Get-AzProximityPlacementGroup -ResourceGroupName $ResourceGroupName -Name $proximity
#    Write-Host "Found proximity placement group"
#} catch {
#    $proximity = New-AzProximityPlacementGroup -ResourceGroupName $ResourceGroupName -Name $proximity -Location $Location -ProximityPlacementGroupType Standard -Zone "1" -IntentVMSizeList $VMSize
#    Write-Host "Created proximity placement group"
#}

Write-Host "[$(Get-Date)] $VMName`: Creating security group"
$nsg = New-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Name "$VMName-Nsg" -Location $Location -Force

if (!$NoPublicIP) {
    Write-Host "[$(Get-Date)] $VMName`: Creating IP address"
    $publicIp = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name "$VMName-PublicIP" -Location $Location -AllocationMethod "Static" -Force

    Write-Host "[$(Get-Date)] $VMName`: Creating network interface card"
    $nic = New-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name "$VMName-Nic" -Location $Location -SubnetId $subnet.Id -PublicIpAddressId $publicIp.Id -NetworkSecurityGroupId $nsg.Id -EnableAcceleratedNetworking -Force
} else {
    Write-Host "[$(Get-Date)] $VMName`: Creating network interface card (no public IP)"
    $nic = New-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name "$VMName-Nic" -Location $Location -SubnetId $subnet.Id -NetworkSecurityGroupId $nsg.Id -EnableAcceleratedNetworking -Force
}

Write-Host "[$(Get-Date)] $VMName`: Creating VM config"
if ($osType -eq "windows") {
    $vmConfig = New-AzVMConfig -VMName $VMName -VMSize $VMSize -SecurityType TrustedLaunch -EnableVtpm $false -EnableSecureBoot $false
    $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Windows -ComputerName $VMName -Credential $cred -ProvisionVMAgent -EnableAutoUpdate
} else {
    $vmConfig = New-AzVMConfig -VMName $VMName -VMSize $VMSize
    $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Linux -ComputerName $VMName -Credential $cred
}
if ($imageByParts) {
    $vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName $image.Split(":")[0] -Offer $image.Split(":")[1] -Skus $image.Split(":")[2] -Version $image.Split(":")[3]
} else {
    $vmConfig = Set-AzVMSourceImage -VM $vmConfig -Id $image
}
$vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id -DeleteOption Delete
$vmConfig = Set-AzVMBootDiagnostic -VM $vmConfig -Enable -ResourceGroupName $ResourceGroupName -StorageAccountName $storage.StorageAccountName

Write-Host "[$(Get-Date)] $VMName`: Creating VM"
New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $vmConfig -OSDiskDeleteOption Delete | Out-Null

# Tag the VM after creation
Write-Host "[$(Get-Date)] $VMName`: Tagging VM with Creation Date, and associated workflow ID"
$vmResourceId = (Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName).Id
$vmCreationTime = Get-Date
Update-AzTag -ResourceId $vmResourceId -Tag @{ "CreationDate" = $vmCreationTime; "WorkFlowId" = $WorkFlowId } -Operation Merge


if ($osType -eq "windows") {
    Write-Host "[$(Get-Date)] $VMName`: Enabling test signing"
    Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $VMName -CommandId "RunPowerShellScript" -ScriptString "bcdedit /set testsigning on" | Out-Null

    Write-Host "[$(Get-Date)] $VMName`: Restarting VM"
    Restart-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName
}

Write-Host "[$(Get-Date)] $VMName`: Complete"
