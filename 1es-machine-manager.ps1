param (
    [string]$Action,
    [string]$GithubContextInput = ""
)

Write-Host "Executing action: $Action"

if ($Action -eq "Deserialize_matrix") {
    $matrix = ConvertFrom-Json $GithubContextInput
    $remote_powershell_supported = $matrix.remote_powershell_supported
    $role = $matrix.role
    $env_str = $matrix.env_str
    echo "remote_powershell_supported=$remote_powershell_supported" >> $env:GITHUB_ENV
    echo "role=$role" >> $env:GITHUB_ENV
    echo "env_str=$env_str" >> $env:GITHUB_ENV
}

if ($Action -eq "Disable_Windows_Defender") {
    # Disable Windows defender / firewall.
    Write-Host "Disabling Windows Defender / Firewall."
    netsh.exe advfirewall set allprofiles state off
    Set-MpPreference -EnableNetworkProtection Disabled
    Set-MpPreference -DisableDatagramProcessing $True
}
