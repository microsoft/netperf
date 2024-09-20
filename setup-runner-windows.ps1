param (
    [Parameter(Mandatory = $false)]
    [string]$Username = "secnetperf",

    [Parameter(Mandatory = $false)]
    [string]$Password,

    [Parameter(Mandatory = $false)]
    [string]$PeerIP,

    [Parameter(Mandatory = $false)]
    [string]$GitHubToken,

    [Parameter(Mandatory = $false)]
    [string]$NewIpAddress,

    [Parameter(Mandatory = $false)]
    [string]$RunnerLabels = "",

    [Parameter(Mandatory = $false)]
    [switch]$SetupRemotePowershell,

    [Parameter(Mandatory = $false)]
    [switch]$SanityCheck,

    [Parameter(Mandatory = $false)]
    [string]$GithubRunnerName = "GenericRunner",

    [Parameter(Mandatory = $false)]
    [switch]$SkipDisableDefender,

    [Parameter(Mandatory = $false)]
    [switch]$IsHost
)

Set-StrictMode -Version 'Latest'
$PSDefaultParameterValues['*:ErrorAction'] = 'Stop'

if ($IsHost) {
    $Username = "localadminuser"
}

if ($SetupRemotePowershell -and $Password) {
    # Install the latest version of PowerShell.
    if ($SkipDisableDefender -or $IsHost) {
        Write-Host "Installing latest PowerShell, WITHOUT enabling PsRemoting."
        iex "& { $(irm https://aka.ms/install-powershell.ps1) } -UseMSI -Quiet"
    } else {
        Write-Host "Installing latest PowerShell, while enabling PsRemoting."
        iex "& { $(irm https://aka.ms/install-powershell.ps1) } -UseMSI -Quiet -EnablePSRemoting"
    }

    if ($SkipDisableDefender -or $IsHost) {
        Write-Host "-SkipDisableDefender set. Skipping Windows Defender / Firewall disabling."
    } else {
        # Disable Windows defender / firewall.
        Write-Host "Disabling Windows Defender / Firewall."
        netsh.exe advfirewall set allprofiles state off
        Set-MpPreference -EnableNetworkProtection Disabled
        Set-MpPreference -DisableDatagramProcessing $True
    }

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

    # Ensure password doesn't expire
    Set-LocalUser -Name $Username -PasswordNeverExpires $true

    # Configure automatic logon.
    Write-Host "Enabling automatic logon."
    REG ADD 'HKLM\Software\Microsoft\Windows NT\CurrentVersion\Winlogon' /v AutoAdminLogon /t REG_SZ /d 1 /f
    REG ADD 'HKLM\Software\Microsoft\Windows NT\CurrentVersion\Winlogon' /v DefaultUserName /t REG_SZ /d $Username /f
    REG ADD 'HKLM\Software\Microsoft\Windows NT\CurrentVersion\Winlogon' /v DefaultPassword /t REG_SZ /d $Password /f
} else {
    Write-Host "-SetupRemotePowershell not set, and/or -Password not provided. Skipping remote powershell setup."
}

if ($PeerIp) {
    # Enable PowerShell remoting to peer.
    Write-Host "Enabling Remote PowerShell to peer."
    "$PeerIp netperf-peer" | Out-File -Encoding ASCII -Append "$env:SystemRoot\System32\drivers\etc\hosts"
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value 'netperf-peer' -Force
} else {
    Write-Host "-PeerIp not provided. Skipping remote powershell setup."
}

if ($GitHubToken -and $Password) {
    # Download and install the GitHub runner.
    Write-Host "Installing GitHub Runner."
    mkdir C:\actions-runner | Out-Null
    Set-Location C:\actions-runner
    $RunnerVersion = "2.313.0"
    $RunnerName = "actions-runner-win-x64-$RunnerVersion.zip"
    Invoke-WebRequest -Uri "https://github.com/actions/runner/releases/download/v$RunnerVersion/$RunnerName" -OutFile $RunnerName
    Add-Type -AssemblyName System.IO.Compression.FileSystem ; [System.IO.Compression.ZipFile]::ExtractToDirectory("$PWD/$RunnerName", "$PWD")
    ./config.cmd --url https://github.com/microsoft/netperf --token $GitHubToken --runasservice --windowslogonaccount $Username --windowslogonpassword $Password --unattended --labels $RunnerLabels --name $GithubRunnerName
} else {
    Write-Host "-GithubToken and/or -Password not provided. Skipping GitHub runner setup."
}

if ($NewIpAddress) {
    # Set the new IP address.
    Write-Host "Setting new IP address..."
    $idx = (Get-NetAdapter | where { $_.LinkSpeed -eq '200 Gbps' }).ifIndex
    New-NetIpAddress -AddressFamily IPv4 -ifindex $idx -IPAddress $NewIpAddress -DefaultGateway "192.168.0.1" -PrefixLength 24
    ipconfig
} else {
    Write-Host "-NewIpAddress not provided. Skipping IP address setup."
}

if ($SanityCheck) {
    $username = (Get-ItemProperty 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon').DefaultUserName
    $password = (Get-ItemProperty 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon').DefaultPassword | ConvertTo-SecureString -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential ($username, $password)
    $Session = New-PSSession -ComputerName 'netperf-peer' -Credential $cred -ConfigurationName PowerShell.7
    # Make sure no errors in running any of these commands on the client machine
    $Session
} else {
    Write-Host "-SanityCheck not set. Skipping sanity check."
}
