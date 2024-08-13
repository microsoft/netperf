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

First, make sure you set bootdebug to be off.

Before restarting, run in an elevated powershell terminal:
- bcdedit /set debug off
- bcdedit /set bootdebug off

#### BIOS Configuration

The following changes must be made to each lab machine from the default configuration:

- Processor Settings -> Kernel DMA Protection -> Enabled
- Integrated Devices -> SR-IOV Global Enable -> Enabled
- System Profile Settings -> System Profile -> Performance

### Hyper-V
By default, hyper-V won't be enabled on the lab machines. You need to enable it via "turn windows features on or off"

Just make sure to select all network adapters available on the host in the wizard. You should leave all others options to their default values.

**Set Secure Boot To Off**
Once you have downloaded and setup your VM on hyper-V, you need to turn secure boot off in the hyper-V settings.

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


# Set up

The following instructions are required to set up each machine in the pool.

### NOTE: For lab scenarios, you need to assign an IP address to the VM.

## Windows Azure Configuration (Deprecated in favor of 1ES)

The following steps are required to set up each machine in the pool.

```PowerShell
$username = 'secnetperf'
$password = '************' # Ask for the password to use
$token = '************'    # Find at https://github.com/microsoft/netperf/settings/actions/runners/new?arch=x64&os=win
$machine1 = '10.1.0.8'     # This is the GitHub runner machine's IP address. Find on the Azure Portal.
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

## Windows Lab Configuration

```PowerShell
$username = 'Administrator'
$password = '************' # Ask for the password to use
$token = '************'    # Find at https://github.com/microsoft/netperf/settings/actions/runners/new?arch=x64&os=win
$machine1 = '192.168.0.XXX' # This is the GitHub runner machine's IP address (XXX is host machine ID + 1)
$machine2 = '192.168.0.YYY' # This is the peer machine's IP address (YYY is host machine ID + 1)
$url = "https://raw.githubusercontent.com/microsoft/netperf/main/setup-runner-windows.ps1"
$labels = "whatever_labels_you_want_tagged"
```

```PowerShell
# Run on GitHub runner machine
# Download the script from $url
Invoke-WebRequest -Uri $url -OutFile setup-runner-windows.ps1
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\setup-runner-windows.ps1 -Username $username -Password $password -PeerIp $machine2 -GithubToken $token -NewIpAddress $machine1 -RunnerLabels $labels
```

```PowerShell
# Run on peer machine
# Download the script from $url
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\setup-runner-windows.ps1 -Username $username -Password $password -PeerIp $machine1 -NewIpAddress $machine2 -RunnerLabels $labels
```

## Linux Azure Configuration (Deprecated in favor of 1ES)

```Shell
# Run on Github runner machine
curl https://raw.githubusercontent.com/microsoft/netperf/main/setup-runner-linux.sh -o setup-runner-linux.sh

CLIENTIP='10.0.0.1' # This is the Github runner machine's IP address. Find on the Azure Portal.
SERVERIP='10.0.0.2'
TOKEN='obtain from https://github.com/microsoft/netperf/settings/actions/runners/new?arch=x64&os=win'
USERNAME='secnetperf'
PASSWORD='...' # Choose a password. Make this consistent.

bash setup-runner-linux.sh -i $SERVERIP -g $TOKEN -u $USERNAME -p $PASSWORD -n
ssh-copy-id $USERNAME@$SERVERIP # or you can run ssh-copy-id $USERNAME@netperf-peer
```

```Shell
# Run on Peer machine
curl https://raw.githubusercontent.com/microsoft/netperf/main/setup-runner-linux.sh -o setup-runner-linux.sh

CLIENTIP='10.0.0.1' # This is the Github runner machine's IP address. Find on the Azure Portal.
SERVERIP='10.0.0.2'
USERNAME='secnetperf'
PASSWORD='...' # Choose a password. Make this consistent.

bash setup-runner-linux.sh -i $CLIENTIP -g $TOKEN -u $USERNAME -p $PASSWORD -n
```

## Linux Lab Configuration

```Shell
# Run on Github runner machine
curl https://raw.githubusercontent.com/microsoft/netperf/main/setup-runner-linux.sh -o setup-runner-linux.sh

# As per our conventions, XXX should be the host ID (RR1-NETPERF-20) plus 1 (192.168.0.21 for the example)
CLIENTIP='192.168.0.XXX/24'
sudo apt install net-tools -y

ifconfig # From the output of ifconfig, look for the netadapter (eth0 or eth1 ...) WITHOUT an inet ipv4 address. Usually, this will be eth1.
sudo ip addr add $CLIENTIP dev eth1 # make sure eth1 is indeed the netadapter without an inet ipv4 address.
# Also create a startup script that runs "sudo ip addr add $CLIENTIP dev eth_" so when the VM restarts, the ip persists.

```

```Shell
# Run on peer machine
curl https://raw.githubusercontent.com/microsoft/netperf/main/setup-runner-linux.sh -o setup-runner-linux.sh

CLIENTIP='192.168.0.XXX'
SERVERIP='192.168.0.YYY/24'
USERNAME='secnetperf'
PASSWORD='...' # Choose a secure password, remember to keep it consistent.

sudo apt install net-tools -y
ifconfig # From the output of ifconfig, look for the netadapter (eth0 or eth1 ...) WITHOUT an inet ipv4 address. Usually, this will be eth1.

sudo ip addr add $SERVERIP dev eth1 # make sure eth1 is indeed the netadapter without an inet ipv4 address.
# Also create a startup script that runs "sudo ip addr add $CLIENTIP dev eth_" so when the VM restarts, the ip persists.

bash setup-runner-linux.sh -i $CLIENTIP -u $USERNAME -p $PASSWORD -n
```

```Shell
# Run on the Github Runner machine
TOKEN='obtain from https://github.com/microsoft/netperf/settings/actions/runners/new?arch=x64&os=linux'
USERNAME='secnetperf'
PASSWORD='...' # Choose a secure password, remember to keep it consistent.
SERVERIP='192.168.0.YYY'
bash setup-runner-linux.sh -i $SERVERIP -g $TOKEN -u $USERNAME -p $PASSWORD -n

ping netperf-peer # Sanity check
ssh-keygen -t rsa -N "" -f $HOME/.ssh/id_rsa
sudo ssh-copy-id $USERNAME@$SERVERIP # Or sudo ssh-copy-id $USERNAME@netperf-peer

pwsh
```
Once loaded up in powershell:
```Powershell
# Still on the Github Runner machine:
# Final Sanity Check to make sure the pair of VMs / machines are fully onboarded.
$Username = "secnetperf"
$Session = New-PSSession -HostName "netperf-peer" -UserName $UserName -SSHTransport # Make sure no errors here.
```

On Lab Linux, our setup-ipaddr-linux.sh scripts use the `ip` util to assign an IP to the VM, and create a startup script that assigns that do the same thing. The IP address should be a fixed value depending on the machine ID of the lab host.

Our script will run: `sudo ip addr add (address / CIDR block) dev (NIC name)`. This solves the problem where if you reboot, Linux will revert your IP assignments. So what you do is you can create a startup script that runs on boot leveraging `systemd` or some other service depending on your Linux distro.

Our convention is to set the IP address to `192.168.0.(machine ID + 1)`. So machine RR1-NETPERF-20 would get assigned IP address `192.168.0.21`.
