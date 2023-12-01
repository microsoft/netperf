
param(
    [string]$ref = 'manual'
)

$Date = Get-Date -Format "yyyy-MM-dd-HH-mm-ss"

$RunName = "$Date._.$ref"

$env:GIT_REDIRECT_STDERR = '2>&1'

mv test_result.json "$RunName.json"
mv "$RunName.json" ./data/secnetperf
git config user.email "quicdev@microsoft.com"
git config user.name "QUIC Dev[bot]"
git add ./data
git status
git commit -m "Add test results for $RunName"
git pull
git push
