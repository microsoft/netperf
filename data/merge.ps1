# Takes the last N runs {sorted by date} and merges them into a single file. Exportable to CSV.

param(
    [Parameter(Mandatory = $false)]
    [int]$LastN = 20,

    [Parameter(Mandatory = $false)]
    [string]$Tool = 'secnetperf',

    [Parameter(Mandatory = $false)]
    [string]$Export = 'JSON' # Can be 'JSON' or 'CSV' or some other SQL-friendly format.
)

if ($Tool -eq 'secnetperf') {
    $Path = './data/secnetperf'

    # Define the path of the parent directory
    $parentDirectory = "./data/secnetperf"

    # Get all directories in the parent directory and sort them lexicographically
    $directories = Get-ChildItem -Path $parentDirectory -Directory | Sort-Object Name

    $i = 0

    # Initialize an array to hold all JSON objects
    $jsonArray = @()

    # Iterate over each directory
    foreach ($dir in $directories) {

        # Increment the counter
        $i++

        if ($i -gt $LastN) {
            break
        }

        # Your logic for each directory goes here
        Write-Host "Processing directory: $($dir.FullName)"

        # Define the path to the test_result.json file in the current directory
        $jsonFilePath = Join-Path $dir.FullName "test_result.json"

        # Check if the file exists
        if (Test-Path $jsonFilePath) {
            # Read the JSON file and convert it to a PowerShell object
            $jsonContent = Get-Content $jsonFilePath | ConvertFrom-Json

            # Add the object to the array
            $jsonArray += $jsonContent
        } else {
            Write-Host "File not found: $jsonFilePath"
        }
    }

    # Convert the array to JSON
    $mergedJson = $jsonArray | ConvertTo-Json

    # Save to secnetperf file
    Set-Content "./data/secnetperf/dashboard.json" -Value $mergedJson

} elseif ($Tool -eq 'xdp') {
    # TODO
} elseif ($Tool -eq 'ebpf') {
    # TODO
} else {
    throw "Unknown tool: $Tool"
}
