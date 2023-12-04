
param(
    [string]$ref = 'manual'
)

# Get the current date and time
$currentDate = Get-Date

# Define the Pacific Standard Time zone ID
# Note: Windows time zones might not use "PST" as the identifier.
# Instead, it often uses specific city names or "Pacific Standard Time"
$pstZoneId = "Pacific Standard Time"

# Get the TimeZoneInfo object for Pacific Standard Time
$pstZone = [TimeZoneInfo]::FindSystemTimeZoneById($pstZoneId)

# Convert the current date and time to Pacific Standard Time
$pstDate = [TimeZoneInfo]::ConvertTime($currentDate, $pstZone)

# Format the date in the "yyyy-MM-dd-HH-mm-ss" format
$formattedDate = $pstDate.ToString("yyyy-MM-dd-HH-mm-ss")

$RunName = $formattedDate

$env:GIT_REDIRECT_STDERR = '2>&1'

mv test_result.json $RunName
mv $RunName ./data/secnetperf
git config user.email "quicdev@microsoft.com"
git config user.name "QUIC Dev[bot]"
git add ./data
git status
git commit -m "Add test results for $ref"
git pull
git push
