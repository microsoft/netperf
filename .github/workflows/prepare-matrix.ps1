
param(
    [Parameter(Mandatory=$false)]
    [string]$MatrixFileName = "quic_matrix.json"
)

Set-StrictMode -Version "Latest"
$PSDefaultParameterValues["*:ErrorAction"] = "Stop"


$MatrixJson = Get-Content -Path .\.github\workflows\$MatrixFileName | ConvertFrom-Json


$AzureJson = @()
$LabJson = @()
$LabJsonStateless = @()
$FullJson = @()

foreach ($entry in $MatrixJson) {
    if ($entry.env -match "azure") {
        $Windows2022Pool = "netperf-actual-boosted-winprerelease" # TODO: "boost-prerelease" name is misleading. Change it to be "boosted-windows-2022".
        $Ubuntu2004Pool = "netperf-boosted-linux-pool" # NOTE: This pool is using experimental boost SKUs.
        $Windows2025Pool = "netperf-boosted-windows-pool" # NOTE: This runs the latest ge_current_directiof_stack build.
        $client = $entry.PSObject.Copy()
        $server = $entry.PSObject.Copy()

        $hasPreferredPoolSku = $entry.PSObject.Properties.Name -contains "preferred_pool_sku"
        if ($hasPreferredPoolSku) {
            if ($entry.preferred_pool_sku -eq "Standard_F8s_v2") {
                $Windows2022Pool = "netperf-f-series-windows-2022"
                $Ubuntu2004Pool = "netperf-f-series-ubuntu-20.04"
            }
        }

        $env_str = [guid]::NewGuid().ToString()
        if ($entry.os -match "windows-2022") {
            $client | Add-Member -MemberType NoteProperty -Name "assigned_pool" -Value $Windows2022Pool
            $server | Add-Member -MemberType NoteProperty -Name "assigned_pool" -Value $Windows2022Pool
            $client | Add-Member -MemberType NoteProperty -Name "remote_powershell_supported" -Value 'FALSE'
            $server | Add-Member -MemberType NoteProperty -Name "remote_powershell_supported" -Value 'FALSE'
        } elseif ($entry.os -match "ubuntu-20.04") {
            $client | Add-Member -MemberType NoteProperty -Name "assigned_pool" -Value $Ubuntu2004Pool
            $server | Add-Member -MemberType NoteProperty -Name "assigned_pool" -Value $Ubuntu2004Pool
            $client | Add-Member -MemberType NoteProperty -Name "remote_powershell_supported" -Value 'FALSE'
            $server | Add-Member -MemberType NoteProperty -Name "remote_powershell_supported" -Value 'FALSE'
        } elseif ($entry.os -match "windows-2025") {
            $client | Add-Member -MemberType NoteProperty -Name "assigned_pool" -Value $Windows2025Pool
            $server | Add-Member -MemberType NoteProperty -Name "assigned_pool" -Value $Windows2025Pool
            $client | Add-Member -MemberType NoteProperty -Name "remote_powershell_supported" -Value 'FALSE'
            $server | Add-Member -MemberType NoteProperty -Name "remote_powershell_supported" -Value 'FALSE'
        } else {
            throw "Invalid OS entry (Must be either windows-2022 or ubuntu-20.04). Got: $($entry.os)"
        }
        $client | Add-Member -MemberType NoteProperty -Name "role" -Value "client"
        $server | Add-Member -MemberType NoteProperty -Name "role" -Value "server"
        $client | Add-Member -MemberType NoteProperty -Name "env_str" -Value $env_str
        $server | Add-Member -MemberType NoteProperty -Name "env_str" -Value $env_str

        if ("in_staging_mode" -in $entry.PSObject.Properties.Name) {
            $client | Add-Member -MemberType NoteProperty -Name "optional" -Value 'TRUE'
            $server | Add-Member -MemberType NoteProperty -Name "optional" -Value 'TRUE'
        } else {
            $client | Add-Member -MemberType NoteProperty -Name "optional" -Value 'FALSE'
            $server | Add-Member -MemberType NoteProperty -Name "optional" -Value 'FALSE'
        }
        $AzureJson += $client
        $AzureJson += $server
        $FullJson += $client
        $FullJson += $server
    } elseif ($entry.env -match "lab-stateless") {
        $labclient = $entry.PSObject.Copy()
        $env_str = [guid]::NewGuid().ToString()
        $labclient.env = "lab"
        $labclient | Add-Member -MemberType NoteProperty -Name "assigned_pool" -Value "NONE"
        $labclient | Add-Member -MemberType NoteProperty -Name "remote_powershell_supported" -Value 'TRUE'
        $labclient | Add-Member -MemberType NoteProperty -Name "role" -Value "client"
        $labclient | Add-Member -MemberType NoteProperty -Name "env_str" -Value $env_str

        if ("in_staging_mode" -in $entry.PSObject.Properties.Name) {
            $labclient | Add-Member -MemberType NoteProperty -Name "optional" -Value 'TRUE'
        } else {
            $labclient | Add-Member -MemberType NoteProperty -Name "optional" -Value 'FALSE'
        }

        $LabJsonStateless += $labclient
        $FullJson += $labclient
    } elseif ($entry.env -match "lab") {
        $labclient = $entry.PSObject.Copy()
        $env_str = [guid]::NewGuid().ToString()
        $labclient | Add-Member -MemberType NoteProperty -Name "assigned_pool" -Value "NONE"
        $labclient | Add-Member -MemberType NoteProperty -Name "remote_powershell_supported" -Value 'TRUE'
        $labclient | Add-Member -MemberType NoteProperty -Name "role" -Value "client"
        $labclient | Add-Member -MemberType NoteProperty -Name "env_str" -Value $env_str

        if ("in_staging_mode" -in $entry.PSObject.Properties.Name) {
            $labclient | Add-Member -MemberType NoteProperty -Name "optional" -Value 'TRUE'
        } else {
            $labclient | Add-Member -MemberType NoteProperty -Name "optional" -Value 'FALSE'
        }

        $LabJson += $labclient
        $FullJson += $labclient
    } else {
        throw "Invalid environment entry (Must be either Azure or Lab or Lab-stateless). Got: $($entry.env)"
    }
}

# Save JSON to file
$LabJson | ConvertTo-Json | Set-Content -Path .\.github\workflows\lab-matrix.json
$AzureJson | ConvertTo-Json | Set-Content -Path .\.github\workflows\azure-matrix.json
$FullJson | ConvertTo-Json | Set-Content -Path .\.github\workflows\full-matrix.json
$LabJsonStateless | ConvertTo-Json | Set-Content -Path .\.github\workflows\lab-stateless-matrix.json
