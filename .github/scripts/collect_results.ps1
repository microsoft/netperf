# Collect results from test runs
Write-Host "Waiting for and collecting test results..."

while ($true) {
    $allRuns = gh run list --repo microsoft/netperf --workflow="network-traffic-performance-linux.yml" --limit 10 --json databaseId,status | ConvertFrom-Json | Where-Object {$_.databaseId -ge 20978067803}
    
    $completedCount = ($allRuns | Where-Object {$_.status -eq 'completed'}).Count
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Completed: $completedCount / 6"
    
    if ($completedCount -ge 6) {
        Write-Host "`n=== RESULTS ===" 
        
        foreach ($run in ($allRuns | Sort-Object databaseId -Descending)) {
            if ($run.status -eq 'completed') {
                $runDir = "results_$($run.databaseId)"
                rm -r $runDir -Force -ErrorAction SilentlyContinue
                gh run download $run.databaseId --repo microsoft/netperf --dir $runDir 2>&1 | Out-Null
                
                $csvFile = "$runDir/echo_test_linux_lab_ubuntu-24.04_x64/echo_summary.csv"
                if (Test-Path $csvFile) {
                    $csv = Get-Content $csvFile | ConvertFrom-Csv
                    Write-Host "Run $($run.databaseId): Sent=$($csv.Sent) Received=$($csv.Received) Rate=$($csv.RecvRate_pps) pps"
                }
            }
        }
        break
    }
    
    Start-Sleep -Seconds 30
}
