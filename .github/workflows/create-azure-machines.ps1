<#
.SYNOPSIS
    Creates a pair of Azure VMs to use for testing.
#>

param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("windows-2022", "windows-2025", "ubuntu-22.04", "ubuntu-20.04", "ubuntu-18.04", "mariner-2")]
    [string]$Os = "windows-2022",

    [Parameter(Mandatory = $false)]
    [ValidateSet("Experimental_Boost4", "Standard_DS2_v2", "Standard_F8s_v2")]
    [string]$VMSize = "Experimental_Boost4",

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "netperf-ex",

    [Parameter(Mandatory = $false)]
    [string]$Location = "South Central US",

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$GitHubToken
)

Set-StrictMode -Version "Latest"
$PSDefaultParameterValues["*:ErrorAction"] = "Stop"

$osType = $Os.Split("-")[0]
$image = "MicrosoftWindowsServer:WindowsServer:2022-datacenter-azure-edition:latest"
if ($Os -eq "windows-2025") {
    Write-Error "Windows 2025 is not supported yet." # TODO - Get this working
} elseif ($Os -eq "ubuntu-22.04") {
    $image = "Canonical:0001-com-ubuntu-server-jammy:22_04-lts:22.04.202403010"
} elseif ($Os -eq "ubuntu-20.04") {
    $image = "Canonical:0001-com-ubuntu-server-focal:20_04-lts:20.04.202402290"
} elseif ($Os -eq "ubuntu-18.04") {
    $image = "Canonical:UbuntuServer:18.04-LTS:latest"
} elseif ($Os -eq "mariner-2") {
    $image = "MicrosoftCBLMariner:cbl-mariner:cbl-mariner-2:2.20240223.01"
}
$username = "secnetperf"
$password = "SecureNetworkPerf!" | ConvertTo-SecureString -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ($username, $password)

if ($SubscriptionId) {
    # Connect to Azure, otherwise assume we're already connected.
    Connect-AzAccount -SubscriptionId $subscriptionId
}

Write-Host "Creating Azure Resources ($ResourceGroupName, $Location, $os, $VMSize)"

try {
    Get-AzResourceGroup -Name $ResourceGroupName | Out-Null
    Write-Host "Found resource group"
} catch {
    New-AzResourceGroup -Name $ResourceGroupName -Location $Location | Out-Null
    Write-Host "Created resource group"
}

$vnetName = "exvnet"
try {
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $vnetName
    Write-Host "Found vnet"
} catch {
    $vnet = New-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $vnetName -Location $Location -AddressPrefix "10.0.0.0/16"
    Write-Host "Created vnet"
}

$subnetName = "exsubnet"
try {
    $subnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $subnetName
    Write-Host "Found subnet config"
} catch {
    $subnet = Add-AzVirtualNetworkSubnetConfig -Name $subnetName -VirtualNetwork $vnet -AddressPrefix "10.0.1.0/24"
    $vnet | Set-AzVirtualNetwork | Out-Null
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $vnetName
    $subnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $subnetName
    Write-Host "Created subnet config"
}

$storageName = "exbootstorage"
try {
    $storage = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $storageName
    Write-Host "Found storage account"
} catch {
    $storage = New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $storageName -Location $Location -SkuName "Standard_LRS"
    Write-Host "Created storage account"
}

function Add-NetPerfVm {
    param ($vmName)

    try {
        Get-AzVM -ResourceGroupName $ResourceGroupName -Name $vmName | Out-Null
        Write-Host "`nFound $vmName already created. Skipping..."
        return
    } catch { }

    Write-Host "`nCreating $vmName"

    Write-Host "$vmName`: Creating IP address" # TODO - Remove need for public IP address
    $publicIp = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name "$vmName-PublicIP" -Location $Location -AllocationMethod "Static" -Force

    Write-Host "$vmName`: Creating security group"
    $nsg = New-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Name "$vmName-Nsg" -Location $Location -Force

    Write-Host "$vmName`: Creating network interface card"
    $nic = New-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name "$vmName-Nic" -Location $Location -SubnetId $subnet.Id -PublicIpAddressId $publicIp.Id -NetworkSecurityGroupId $nsg.Id -EnableAcceleratedNetworking -Force

    Write-Host "$vmName`: Creating VM config"
    if ($osType -eq "windows") {
        $vmConfig = New-AzVMConfig -VMName $vmName -VMSize $VMSize -SecurityType TrustedLaunch -EnableVtpm $false -EnableSecureBoot $false
        $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Windows -ComputerName $vmName -Credential $cred -ProvisionVMAgent -EnableAutoUpdate
    } else {
        $vmConfig = New-AzVMConfig -VMName $vmName -VMSize $VMSize
        $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Linux -ComputerName $vmName -Credential $cred
    }
    $vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName $image.Split(":")[0] -Offer $image.Split(":")[1] -Skus $image.Split(":")[2] -Version $image.Split(":")[3]
    $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id
    $vmConfig = Set-AzVMBootDiagnostic -VM $vmConfig -Enable -ResourceGroupName $ResourceGroupName -StorageAccountName $storage.StorageAccountName

    Write-Host "$vmName`: Creating VM"
    New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $vmConfig | Out-Null

    if ($osType -eq "windows") {
        Write-Host "$vmName`: Enabling test signing"
        Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $vmName -CommandId "RunPowerShellScript" -ScriptString "bcdedit /set testsigning on" | Out-Null

        Write-Host "$vmName`: Restarting VM"
        Restart-AzVM -ResourceGroupName $ResourceGroupName -Name $vmName
    }
}

function Get-NetPerfVmPrivateIp {
    param ($vmName)
    $nic = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name "$vmName-Nic"
    return $nic.IpConfigurations[0].PrivateIpAddress
}

$vmName1 = "ex-$osType-01" # TODO - Dynamically generate numbers
$vmName2 = "ex-$osType-02"

Add-NetPerfVm $vmName1
Add-NetPerfVm $vmName2

if ($GitHubToken) {
    Write-Host "Configuring GitHub for runner"

    $ip1 = Get-NetPerfVmPrivateIp $vmName1
    $ip2 = Get-NetPerfVmPrivateIp $vmName2

    if ($osType -eq "windows") {
        $scriptParams = @{
            "Username" = $username
            "Password" = $password
            "PeerIP" = $ip1
        }
        Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $vmName2 -CommandId "RunPowerShellScript" -ScriptPath ".\setup-runner-windows.ps1" -Parameter $scriptParams | Out-Null

        $scriptParams = @{
            "Username" = $username
            "Password" = $password
            "PeerIP" = $ip2
            "GitHubToken" = $GitHubToken
            "RunnerLabels" = "os-$osType,azure-ex"
        }
        Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $vmName1 -CommandId "RunPowerShellScript" -ScriptPath ".\setup-runner-windows.ps1" -Parameter $scriptParams | Out-Null
    }
}
