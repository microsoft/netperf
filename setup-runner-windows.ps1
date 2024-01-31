param (
    [Parameter(Mandatory = $false)]
    [string]$Username = "secnetperf",

    [Parameter(Mandatory = $true)]
    [string]$Password,

    [Parameter(Mandatory = $true)]
    [string]$PeerIP,

    [Parameter(Mandatory = $false)]
    [string]$GitHubToken,

    [Parameter(Mandatory = $false)]
    [switch]$NoReboot = $false,

    [Parameter(Mandatory = $false)]
    [string]$NewIpAddress
)

Set-StrictMode -Version 'Latest'
$PSDefaultParameterValues['*:ErrorAction'] = 'Stop'

$RebootRequired = $false

# Install the latest version of PowerShell.
Write-Host "Installing latest PowerShell."
iex "& { $(irm https://aka.ms/install-powershell.ps1) } -UseMSI" # TODO - Get silent install working

# Check to see if test signing is enabled.
$HasTestSigning = $false
try { $HasTestSigning = ("$(bcdedit)" | Select-String -Pattern "testsigning\s+Yes").Matches.Success } catch { }

# Enable test signing as necessary.
if (!$HasTestSigning) {
    # Enable test signing.
    Write-Host "Enabling Test Signing."
    bcdedit /set testsigning on | Write-Verbose
    $RebootRequired = $true
}

# Enable PowerShell remoting to peer.
Write-Host "Enabling Remote PowerShell."
"$PeerIp netperf-peer" | Out-File -Encoding ASCII -Append "$env:SystemRoot\System32\drivers\etc\hosts"
pwsh -Command 'Enable-PSRemoting -Force'
Set-Item WSMan:\localhost\Client\TrustedHosts -Value 'netperf-peer'

# Disable Windows defender / firewall.
Write-Host "Disabling Windows Defender / Firewall."
netsh.exe advfirewall set allprofiles state off
Set-MpPreference -EnableNetworkProtection Disabled
Set-MpPreference -DisableDatagramProcessing $True

# Make sure the user has the rights to log on.
function Add-ServiceLogonRight ($Username) {
    $tmp = New-TemporaryFile
    secedit /export /cfg "$tmp.inf" | Out-Null
    (Get-Content -Encoding ascii "$tmp.inf") -replace '^SeServiceLogonRight .+', "`$0,$Username" | Set-Content -Encoding ascii "$tmp.inf"
    secedit /import /cfg "$tmp.inf" /db "$tmp.sdb" | Out-Null
    secedit /configure /db "$tmp.sdb" /cfg "$tmp.inf" | Out-Null
    Remove-Item $tmp* -ErrorAction SilentlyContinue
}
Write-Host "Enabling ServiceLogonRight."
Add-ServiceLogonRight -Username $Username

# Configure automatic logon.
Write-Host "Enabling automatic logon."
REG ADD 'HKLM\Software\Microsoft\Windows NT\CurrentVersion\Winlogon' /v AutoAdminLogon /t REG_SZ /d 1 /f
REG ADD 'HKLM\Software\Microsoft\Windows NT\CurrentVersion\Winlogon' /v DefaultUserName /t REG_SZ /d $Username /f
REG ADD 'HKLM\Software\Microsoft\Windows NT\CurrentVersion\Winlogon' /v DefaultPassword /t REG_SZ /d $Password /f

if ($GitHubToken) {
    # Download and install the GitHub runner.
    Write-Host "Installing GitHub Runner."
    mkdir C:\actions-runner | Out-Null
    Set-Location C:\actions-runner
    $RunnerVersion = "2.312.0"
    $RunnerName = "actions-runner-win-x64-$RunnerVersion.zip"
    Invoke-WebRequest -Uri "https://github.com/actions/runner/releases/download/v$RunnerVersion/$RunnerName" -OutFile $RunnerName
    Add-Type -AssemblyName System.IO.Compression.FileSystem ; [System.IO.Compression.ZipFile]::ExtractToDirectory("$PWD/$RunnerName", "$PWD")
    ./config.cmd --url https://github.com/microsoft/netperf --token $GitHubToken --runasservice --windowslogonaccount $Username --windowslogonpassword $Password --unattended
}

if ($NewIpAddress) {
    # Set the new IP address.
    Write-Host "Setting new IP address..."
    $idx = (Get-NetAdapter | where { $_.LinkSpeed -eq '200 Gbps' }).ifIndex
    New-NetIpAddress -AddressFamily IPv4 -ifindex $idx -IPAddress $NewIpAddress -DefaultGateway "192.168.0.1" -PrefixLength 24
    ipconfig
}

# Reboot if necessary.
if ($RebootRequired) {
    if ($NoReboot) {
        Write-Host "Reboot Required!"
    } else {
        Write-Host "Rebooting in 5 seconds..."
        Start-Sleep -Seconds 5
        Restart-Computer -Force
    }
}
