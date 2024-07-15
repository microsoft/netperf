
function ValidateInheritedParams {
    Write-Host "Inherited run id: $env:run_id"
    Write-Host "Inherited role: $env:role"
    Write-Host "Inherited remote_powershell_supported: $env:remote_powershell_supported"
    Write-Host "Inherited api url: $env:api_url"
    $headers = @{
        'secret' = $env:syncer_secret
    }
    Invoke-WebRequest -Uri "$env:api_url/hello" -Headers $headers
}

function NetperfSendCommand {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    # Should send a command to the shared cache and wait for the server process to execute said command before exiting.
}
