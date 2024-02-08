# Hardware

## Dedicated x64 Machines

Based on the [Dell R650](https://i.dell.com/sites/csdocuments/Product_Docs/en/poweredge-r650-spec-sheet.pdf) Rack Server:

- 2 x [Intel Xeon Silver 4316](https://ark.intel.com/content/www/us/en/ark/products/215270/intel-xeon-silver-4316-processor-30m-cache-2-30-ghz.html) (2.3 GHz, 20 Cores / 40 Threads)
- 8 x 16 GB RDIMM, 3200MT/s, Dual Rank
- [Mellanox ConnectX-6 Dx](https://docs.nvidia.com/networking/display/ConnectX6DxEN/Specifications) MCX623105AN-VDAT 200 Gigabit QSFP56 PCIe 4.0 x16
- [480GB SSD](https://www.dell.com/en-us/shop/480gb-ssd-sata-mixed-use-6gbps-512e-25in-hot-plug-s4620/apd/345-bdns/storage-drives-media) SATA Mix Use 6Gbps 512in Hot-plug AG Drive, 3DWPD

All the machines are connected by a 400 GbE [PowerSwitch Z9432F](https://www.delltechnologies.com/asset/en-us/products/networking/technical-support/dell-emc-powerswitch-z9432f-spec-sheet.pdf).

### Setup

The easiest way to automate machine deployment is via `WorkflowCommandLine.exe`, which you need to install (installed automatically in Program Files if you have WTT Studio).

```PowerShell
# Run ./WorkflowCommandLine.exe command for machines 01, 02... 09 for a sanity check first.
for ($i = 10; $i -lt 61; $i++) { ./WorkFlowCommandLine.exe /run /datastore:ServerPlaceholder /identityserver:atlasidentity /identitydatabase:wttidentity /id:251 /resourcedatastore:WTT_EDS09 /machinepool:"$\TestServices\WTT_EDS09\Desktop\Private\NetPerf" /machine:RR1-NetPerf-$i /commonparam:DEPLOY_OS_LAB=fe_release_svc_prod1 /commonparam:DEPLOY_OS_EDITION=ServerDatacenter /commonparam:DEPLOY_OS_PLATFORM=amd64 }
```

## Dedicated arm64 Machines

TODO

## Azure VMs

In additional to dedicated lab machines, we also leverage Azure VMs to test realistic, production environments:

- [Standard F4s v2](https://learn.microsoft.com/en-us/azure/virtual-machines/fsv2-series)
- 4 vCPUs
- 8 GB RAM
- Accelerated Networking Enabled

They are running on the same VNet.

### For Windows Testing

- Use the `netperf` resource group.
- Create a pair of `F4sV2` VMs in the `East US` location.
- Name them `f4-windows-XX` where `XX` is replaced with the next (zero-prefixed) machine number.
- Attach it to the existing vnet, `netperf-secnetperf-win-client-vnet`.
- Use the username ('secnetperf') and password ('************').
- Disable Secure Boot on the VMs.

### For Linux Testing

TLDR;

1. On Azure, create your 2 VMs on Ubuntu 20.04.

2. Change powershell remoting to use SSH instead of WinRM.

3. Link client as a Github self-hosted runner.

# Set up

The following instructions are required to set up each machine in the pool.

## Configuration (Windows)

The following steps are required to set up each machine in the pool.

```PowerShell
$username = 'secnetperf'
$password = '************' # Ask for the password to use
$token = '************'    # Find at https://github.com/microsoft/netperf/settings/actions/runners/new?arch=x64&os=win
$machine1 = '10.1.0.8'     # This is the GitHub runner machine's IP address
$machine2 = '10.1.0.9'     # This is the peer machine's IP address
$url = "https://raw.githubusercontent.com/microsoft/netperf/main/setup-runner-windows.ps1"
```

```PowerShell
# Run on GitHub runner machine
iex "& { $(irm $url) } $username $password $machine2 $token"
```

```PowerShell
# Run on peer machine
iex "& { $(irm $url) } $username $password $machine1"
```

## Configuration (Linux)

```
curl https://raw.githubusercontent.com/microsoft/netperf/main/setup-runner-linux.sh -o setup-runner-linux.sh

bash setup-runner-linux.sh -i <peerip> -g <github token *do this on client only> -n <no reboot *optional>

# Do this on the client only:

ssh-keygen

ssh-copy-id <username of peer>@<peerip>
```

### Troubleshooting Linux

- Sometimes, depending on your specific Linux distro and if you are using Azure, Powershell may not install correctly the first time when running this script. In this instance, if `pwsh --version` can not be found, run `sudo apt-get install powershell -y` after waiting a bit.
