# Hardware

## Dedicated x64 Machines

Based on the [Dell R650](https://i.dell.com/sites/csdocuments/Product_Docs/en/poweredge-r650-spec-sheet.pdf) Rack Server. It has a total of 40 cores and 80 threads, 128 GB of DDR4 RAM, 480 GB of SSD storage, and a 200 Gbps Mellanox CX-6.

- 2 x [Intel Xeon Silver 4316](https://ark.intel.com/content/www/us/en/ark/products/215270/intel-xeon-silver-4316-processor-30m-cache-2-30-ghz.html) (2.3 GHz, 20 Cores / 40 Threads)
- 8 x 16 GB RDIMM, 3200MT/s, Dual Rank
- [Mellanox ConnectX-6 Dx](https://docs.nvidia.com/networking/display/ConnectX6DxEN/Specifications) MCX623105AN-VDAT 200 Gigabit QSFP56 PCIe 4.0 x16
- [480GB SSD](https://www.dell.com/en-us/shop/480gb-ssd-sata-mixed-use-6gbps-512e-25in-hot-plug-s4620/apd/345-bdns/storage-drives-media) SATA Mix Use 6Gbps 512in Hot-plug AG Drive, 3DWPD

All the machines are connected by a 400 GbE [PowerSwitch Z9432F](https://www.delltechnologies.com/asset/en-us/products/networking/technical-support/dell-emc-powerswitch-z9432f-spec-sheet.pdf).

## Dedicated arm64 Machines

TODO

## Azure VMs

Follows a very similar setup below.

## For Windows Testing
TLDR;

1. Create 2 VMs and hook them up to the same VNet. MAKE SURE YOU CREATE THE 2 VMS WITH THE SAME USERNAME AND PASSWORD.
2. Make sure you can ping the other VM and that your host file contains the private IP of the other VM as "netperf-peer"
3. Automation setup:
  a. For MsQuic, we will use a combination of Powershell and a Github Actions workflow.

     Essentially, the goal is, we want to trigger a Github Actions workflow after making new commits to the QUIC repo.
     The workflow file will kickoff a process in the NetPerf repo.

     The netperf repo will essentially first BUILD from the latest commit after checking out the repo, then UPLOAD the artifacts.
     After uploading, the "quic.yml" workflow will then download those built artifacts, and run secnetperf (assume the latest commit is baked into the binary.)

  b. For XDP, very similar to QUIC. BUILD, upload artifacts, download artifacts, then run the various tests / benchmarks.


# Set up

The following instructions are required to set up each machine in the pool.

## Dependencies

The current jobs we execute on these machines have the following dependencies:

- PowerShell 7

## Configuration (Windows)

Once the dependencies have been installed the following configuration must be made:

### Enable Test Signing

```cmd
bcdedit /set testsigning on
```

> **Note** - You may have to disable Secure Boot first.

> **Note** - You will have to reboot after disabling test signing.


### Enable PowerShell Remoting to Peer

```PowerShell
"$PeerIp netperf-peer" | Out-File -Encoding ASCII -Append "$env:SystemRoot\System32\drivers\etc\hosts"
Enable-PSRemoting -Force
Set-Item WSMan:\localhost\Client\TrustedHosts -Value 'netperf-peer'
```

### Disable Windows Defender / Firewall

```PowerShell
netsh.exe advfirewall set allprofiles state off
Set-MpPreference -EnableNetworkProtection Disabled
Set-MpPreference -DisableDatagramProcessing $True
```

### Give the User Service Logon Rights

```PowerShell
function Add-ServiceLogonRight ($Username) {
  Write-Host "Enable ServiceLogonRight for $Username"
  $tmp = New-TemporaryFile
  secedit /export /cfg "$tmp.inf" | Out-Null
  (Get-Content -Encoding ascii "$tmp.inf") -replace '^SeServiceLogonRight .+', "`$0,$Username" | Set-Content -Encoding ascii "$tmp.inf"
  secedit /import /cfg "$tmp.inf" /db "$tmp.sdb" | Out-Null
  secedit /configure /db "$tmp.sdb" /cfg "$tmp.inf" | Out-Null
  Remove-Item $tmp* -ErrorAction SilentlyContinue
}

Add-ServiceLogonRight -Username netperf
```

### Install the GitHub Runner Agent

https://github.com/microsoft/netperf/settings/actions/runners/new?arch=x64

> **Note** - Install as a service.

> **Note** - Configure appropriate tags.

Then, configure the service to run as the user:

```PowerShell
$name = "netperf-win1"
$password = "****************"
sc.exe config "actions.runner.microsoft-netperf.$name" obj= ".\netperf" password= $password type= own
sc.exe stop "actions.runner.microsoft-netperf.$name"
sc.exe start "actions.runner.microsoft-netperf.$name"
```

## Configuration (Linux)

TODO
