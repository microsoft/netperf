
function NetperfSendCommand {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    Write-Host "Inherited run id: $env:run_id"
}

