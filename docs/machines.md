# Hardware

We run our tests on a variety of hardware to ensure that our performance measurements are accurate and repeatable. We use a combination of dedicated machines in a lab environment and virtual machines in Azure. The following sections detail the hardware we use for testing.

## Lab x64 Machines

We have a set of dedicated machines in a lab environment for testing. Each machine hosts a single virtual machine that is used to run the tests.

Based on the [Dell R650](https://i.dell.com/sites/csdocuments/Product_Docs/en/poweredge-r650-spec-sheet.pdf) Rack Server:

- 2 x [Intel Xeon Silver 4316](https://ark.intel.com/content/www/us/en/ark/products/215270/intel-xeon-silver-4316-processor-30m-cache-2-30-ghz.html) (2.3 GHz, 20 Cores / 40 Threads)
- 8 x 16 GB RDIMM, 3200MT/s, Dual Rank
- [Mellanox ConnectX-6 Dx](https://docs.nvidia.com/networking/display/ConnectX6DxEN/Specifications) MCX623105AN-VDAT 200 Gigabit QSFP56 PCIe 4.0 x16
- [480GB SSD](https://www.dell.com/en-us/shop/480gb-ssd-sata-mixed-use-6gbps-512e-25in-hot-plug-s4620/apd/345-bdns/storage-drives-media) SATA Mix Use 6Gbps 512in Hot-plug AG Drive, 3DWPD

All the machines are connected by a 400 GbE [PowerSwitch Z9432F](https://www.delltechnologies.com/asset/en-us/products/networking/technical-support/dell-emc-powerswitch-z9432f-spec-sheet.pdf).

### Setup

#### BIOS Configuration

The following changes must be made to each lab machine from the default configuration:

- Processor Settings -> Kernel DMA Protection -> Enabled
- Integrated Devices -> SR-IOV Global Enable -> Enabled
- System Profile Settings -> System Profile -> Performance

#### OS Deployment

The easiest way to automate machine deployment is via `WorkflowCommandLine.exe`, which you need to install (installed automatically in Program Files if you have WTT Studio).

```PowerShell
# Run ./WorkflowCommandLine.exe command for machines 01, 02... 09 for a sanity check first.
for ($i = 10; $i -lt 61; $i++) { ./WorkFlowCommandLine.exe /run /datastore:ServerPlaceholder /identityserver:atlasidentity /identitydatabase:wttidentity /id:251 /resourcedatastore:WTT_EDS09 /machinepool:"$\TestServices\WTT_EDS09\Desktop\Private\NetPerf" /machine:RR1-NetPerf-$i /commonparam:DEPLOY_OS_LAB=fe_release_svc_prod1 /commonparam:DEPLOY_OS_EDITION=ServerDatacenter /commonparam:DEPLOY_OS_PLATFORM=amd64 }
```

Once the OS is installed, run [`setup-host.ps1`](/setup-host.ps1) on each machine to apply the host configuration.

## Lab ARM64 Machines

_We are in the process of procuring dedicated arm64 machines for testing._

## Azure Virtual Machines

We also leverage Azure VMs to test realistic, production environments:

- Experimental Boost4 series (not publicly available)
- 4 vCPUs
- 8 GB RAM
- [Microsoft Azure Network Adapter](https://learn.microsoft.com/en-us/azure/virtual-network/accelerated-networking-mana-overview)
- Accelerated Networking Enabled
- 25 Gbps Max Network Bandwidth

The VMs are connected by a shared virtual network.
