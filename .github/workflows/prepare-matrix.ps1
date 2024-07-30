
param(
    [Parameter(Mandatory=$false)]
    [string]$MatrixFileName = "quic_matrix.json"
)

Set-StrictMode -Version "Latest"
$PSDefaultParameterValues["*:ErrorAction"] = "Stop"


$MatrixJson = Get-Content -Path .\.github\workflows\$MatrixFileName | ConvertFrom-Json


$AzureJson = @()
$LabJson = @()
$FullJson = @()

foreach ($entry in $MatrixJson) {
    if ($entry.env -match "azure") {
        # $Windows2022Pool = "netperf-boosted-windows-pool"
        $Windows2022Pool = "netperf-aztestpool"
        $Ubuntu2004Pool = "netperf-boosted-linux-pool"
        $client = $entry.PSObject.Copy()
        $server = $entry.PSObject.Copy()
        $env_str = [guid]::NewGuid().ToString()
        if ($entry.os -match "windows-2022") {
            $client | Add-Member -MemberType NoteProperty -Name "assigned_pool" -Value $Windows2022Pool
            $server | Add-Member -MemberType NoteProperty -Name "assigned_pool" -Value $Windows2022Pool
            $client | Add-Member -MemberType NoteProperty -Name "remote_powershell_supported" -Value 'FALSE'
            $server | Add-Member -MemberType NoteProperty -Name "remote_powershell_supported" -Value 'FALSE'
        }
        elseif ($entry.os -match "ubuntu-20.04") {
            $client | Add-Member -MemberType NoteProperty -Name "assigned_pool" -Value $Ubuntu2004Pool
            $server | Add-Member -MemberType NoteProperty -Name "assigned_pool" -Value $Ubuntu2004Pool
            $client | Add-Member -MemberType NoteProperty -Name "remote_powershell_supported" -Value 'FALSE'
            $server | Add-Member -MemberType NoteProperty -Name "remote_powershell_supported" -Value 'FALSE'
        } else {
            throw "Invalid OS entry (Must be either windows-2022 or ubuntu-20.04). Got: $($entry.os)"
        }
        $client | Add-Member -MemberType NoteProperty -Name "role" -Value "client"
        $server | Add-Member -MemberType NoteProperty -Name "role" -Value "server"
        $client | Add-Member -MemberType NoteProperty -Name "env_str" -Value $env_str
        $server | Add-Member -MemberType NoteProperty -Name "env_str" -Value $env_str
        $AzureJson += $client
        $AzureJson += $server
        $FullJson += $client
        $FullJson += $server
    } elseif ($entry.env -match "lab") {
        $labclient = $entry.PSObject.Copy()
        $env_str = [guid]::NewGuid().ToString()
        $labclient | Add-Member -MemberType NoteProperty -Name "assigned_pool" -Value "NONE"
        $labclient | Add-Member -MemberType NoteProperty -Name "remote_powershell_supported" -Value 'FALSE'
        $labclient | Add-Member -MemberType NoteProperty -Name "role" -Value "client"
        $labclient | Add-Member -MemberType NoteProperty -Name "env_str" -Value $env_str
        $LabJson += $entry
        $FullJson += $entry
    } else {
        throw "Invalid environment entry (Must be either Azure or Lab). Got: $($entry.env)"
    }
}

# Save JSON to file
$LabJson | ConvertTo-Json | Set-Content -Path .\.github\workflows\lab-matrix.json
$AzureJson | ConvertTo-Json | Set-Content -Path .\.github\workflows\azure-matrix.json
$FullJson | ConvertTo-Json | Set-Content -Path .\.github\workflows\full-matrix.json
