param (
    [string]$Matrix,
    [string]$GithubRunId,
    [string]$SyncerSecret
)

$DeserializedMatrix = ConvertFrom-Json $Matrix

$Boolean = @('TRUE', 'FALSE')
$ValidRoles = @('client', 'server')

if (!($Boolean -contains $DeserializedMatrix.remote_powershell_supported)) {
    throw "Invalid remote_powershell_supported value: $($DeserializedMatrix.remote_powershell_supported). Did you forget to run prepare-matrix.ps1?"
    exit 1
}

if (!($ValidRoles -contains $DeserializedMatrix.role)) {
    throw "Invalid role value: $($DeserializedMatrix.role). Did you forget to run prepare-matrix.ps1?"
    exit 1
}

$envstr = $DeserializedMatrix.env_str

if ($envstr.Length -lt 1 -or $GithubRunId.Length -lt 1) {
    throw "Invalid env_str inputs and / or run_id"
    exit 1
}

Write-Host "Current environment string: $envstr"

$env:remote_powershell_supported = $DeserializedMatrix.remote_powershell_supported
$env:role = $DeserializedMatrix.role
$env:run_id = "$GithubRunId-$envstr-state"
$env:api_url = "https://netperfapi.azurewebsites.net"
$env:syncer_secret = $SyncerSecret
