# Hardware

## Dedicated x64 Machines

Based on the [Dell R650](https://i.dell.com/sites/csdocuments/Product_Docs/en/poweredge-r650-spec-sheet.pdf) Rack Server. It has a total of 40 cores and 80 threads, 128 GB of DDR4 RAM, 480 GB of SSD storage, and a 200 Gbps Mellanox CX-6.

- 2 x [Intel Xeon Silver 4316](https://ark.intel.com/content/www/us/en/ark/products/215270/intel-xeon-silver-4316-processor-30m-cache-2-30-ghz.html) (2.3 GHz, 20 Cores / 40 Threads)
- 8 x 16 GB RDIMM, 3200MT/s, Dual Rank
- [Mellanox ConnectX-6 Dx](https://docs.nvidia.com/networking/display/ConnectX6DxEN/Specifications) MCX623105AN-VDAT 200 Gigabit QSFP56 PCIe 4.0 x16
- [480GB SSD](https://www.dell.com/en-us/shop/480gb-ssd-sata-mixed-use-6gbps-512e-25in-hot-plug-s4620/apd/345-bdns/storage-drives-media) SATA Mix Use 6Gbps 512in Hot-plug AG Drive, 3DWPD

All the machines are connected by a 400 GbE [PowerSwitch Z9432F](https://www.delltechnologies.com/asset/en-us/products/networking/technical-support/dell-emc-powerswitch-z9432f-spec-sheet.pdf).

Provisioning steps with WTT (Atlas Studio)

Normally, you would use Atlas Studio (netperf pool) to provision your machines.

However, that process is long and cumbersome if we have 60 machines.

Therefore, a way to automate this is with the `WorkflowCommandLine.exe`, which you need to install (installed automatically in Program Files if you have WTT Studio).

```

# Run ./WorkflowCommandLine.exe command for machines 01, 02... 09 for a sanity check first.

for ($i = 10; $i -lt 61; $i++) { ./WorkFlowCommandLine.exe /run /datastore:ServerPlaceholder /identityserver:atlasidentity /identitydatabase:wttidentity /id:251 /resourcedatastore:WTT_EDS09 /machinepool:"$\TestServices\WTT_EDS09\Desktop\Private\NetPerf" /machine:RR1-NetPerf-$i /commonparam:DEPLOY_OS_LAB=fe_release_svc_prod1 /commonparam:DEPLOY_OS_EDITION=ServerDatacenter /commonparam:DEPLOY_OS_PLATFORM=amd64
>>  }
```


## Dedicated arm64 Machines

TODO

## Azure VMs

- [Standard F4s v2](https://learn.microsoft.com/en-us/azure/virtual-machines/fsv2-series)
- 4 vCPUs
- 8 GB RAM
- Accelerated Networking Enabled

They are running on the same VNet.

### For Windows Testing

Create the machines with the same username ('secnetperf') and password ('************').

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
$password = '************'
$token = '************'
$machine1 = '10.1.0.8'
$machine2 = '10.1.0.9'
$url = "https://raw.githubusercontent.com/microsoft/netperf/main/setup-runner-windows.ps1"

# Install on Github runner machine
iex "& { $(irm $url) } $username $password $machine2 $token"

# Install on peer machine
iex "& { $(irm $url) } $username $password $machine1"
```

**Note:**

- Ask for the password to use.
- Get the token from https://github.com/microsoft/netperf/settings/actions/runners/new?arch=x64&os=win

## Configuration (Linux)

```
curl https://raw.githubusercontent.com/microsoft/netperf/main/setup-runner-linux.ps1 -o setup-runner-linux.sh

bash setup-runner-linux.sh -i <peerip> -g <github token *optional> -n <no reboot *optional>

ssh-keygen

ssh-copy-id <username of peer>@<peerip>
```
