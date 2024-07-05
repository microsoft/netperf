
param(
    [Parameter(Mandatory=$false)]
    [string]$MatrixFileName = "quic_matrix.json"
)

Set-StrictMode -Version "Latest"
$PSDefaultParameterValues["*:ErrorAction"] = "Stop"


$MatrixJson = Get-Content -Path .\.github\workflows\$MatrixFileName | ConvertFrom-Json


$AzureJson = @()
$LabJson = @()

foreach ($entry in $MatrixJson) {
    if ($entry.env -match "azure") {
        $Windows2022Pool = "netperf-aztestpool"
        $Ubuntu2004Pool = "netperf-boosted-linux-pool"
        $client = $entry.PSObject.Copy()
        $server = $entry.PSObject.Copy()
        $env_str = "$($entry.os)-$($entry.arch)-$($entry.tls)-$($entry.io)"
        if ($entry.os -match "windows-2022") {
            $client | Add-Member -MemberType NoteProperty -Name "assigned_pool" -Value $Windows2022Pool
            $server | Add-Member -MemberType NoteProperty -Name "assigned_pool" -Value $Windows2022Pool
            $client | Add-Member -MemberType NoteProperty -Name "remote_powershell_supported" -Value 'TRUE'
            $server | Add-Member -MemberType NoteProperty -Name "remote_powershell_supported" -Value 'TRUE'
        }
        if ($entry.os -match "ubuntu-20.04") {
            $client | Add-Member -MemberType NoteProperty -Name "assigned_pool" -Value $Ubuntu2004Pool
            $server | Add-Member -MemberType NoteProperty -Name "assigned_pool" -Value $Ubuntu2004Pool
            $client | Add-Member -MemberType NoteProperty -Name "remote_powershell_supported" -Value 'FALSE'
            $server | Add-Member -MemberType NoteProperty -Name "remote_powershell_supported" -Value 'FALSE'
        }
        $client | Add-Member -MemberType NoteProperty -Name "role" -Value "client"
        $server | Add-Member -MemberType NoteProperty -Name "role" -Value "server"
        $client | Add-Member -MemberType NoteProperty -Name "env_str" -Value $env_str
        $server | Add-Member -MemberType NoteProperty -Name "env_str" -Value $env_str
        $AzureJson += $client
        $AzureJson += $server
    } else {
        $LabJson += $entry
    }
}

# Save JSON to file
$LabJson | ConvertTo-Json | Set-Content -Path .\.github\workflows\processed-matrix.json
$AzureJson | ConvertTo-Json | Set-Content -Path .\.github\workflows\azure-matrix.json
