<#

TODO: Once we migrate off of quic.yml to remove the test execution dependency on MsQuic, update the Test Logic of this script.

For now, just work off of quic.yml and MsQuic.

NOTE:

This script assumes the latest MsQuic commit is built and downloaded as artifacts in the current session.

.PARAMETER LogProfile
    Configures the logging scope for the test. None by default.

.PARAMETER MsQuicCommit
    The MsQuic commit to use for the test. Defaults to "manual" which means the latest commit built and downloaded as artifacts in the current session.

.PARAMETER plat

.PARAMETER os

.PARAMETER arch

.PARAMETER tls

#>

param (
    [ValidateSet("", "NULL", "Basic.Light", "Datapath.Light", "Datapath.Verbose", "Stacks.Light", "Stacks.Verbose", "RPS.Light", "RPS.Verbose", "Performance.Light", "Basic.Verbose", "Performance.Light", "Performance.Verbose", "Full.Light", "Full.Verbose", "SpinQuic.Light", "SpinQuicWarnings.Light")]
    [string]$LogProfile = "",

    [string]$MsQuicCommit = "manual",

    [string]$plat = "windows",

    [string]$os = "windows server 2022",

    [string]$arch = "x64",

    [string]$tls = "schannel"
)

# Set up the connection to the peer over remote powershell.
Write-Output "Connecting to netperf-peer..."
$Session = New-PSSession -ComputerName "netperf-peer" -ConfigurationName PowerShell.7
if ($null -eq $Session) {
    Write-Error "Failed to create remote session"
    exit
}
$RemoteAddress = $Session.ComputerName
Write-Output "Successfully conencted to peer: $RemoteAddress"

# Make sure nothing is running from a previous run.
Invoke-Command -Session $Session -ScriptBlock {
    Get-Process | Where-Object { $_.Name -eq "secnetperf.exe" } | Stop-Process
}

# Copy the artifacts to the peer.
Write-Output "Copying files to peer..."
Invoke-Command -Session $Session -ScriptBlock {
    Remove-Item -Force -Recurse "C:\_work" -ErrorAction Ignore
}
Copy-Item -ToSession $Session .\artifacts -Destination C:\_work\secnetperf\artifacts -Recurse
Copy-Item -ToSession $Session .\msquic\scripts -Destination C:\_work\secnetperf\msquic\scripts -Recurse

try {

mkdir .\artifacts\logs | Out-Null

# Prepare the machines for the testing.
Write-Output "Preparing machines for testing..."
.\msquic\scripts\prepare-machine.ps1 -ForTest
Invoke-Command -Session $Session -ScriptBlock {
    C:\_work\secnetperf\msquic\scripts\prepare-machine.ps1 -ForTest
}

# Logging to collect quic traces while running the tests.

if ($LogProfile -ne "" -and $LogProfile -ne "NULL") {
    Write-Output "Starting logging with log profile: $LogProfile..."
    .\msquic\scripts\log.ps1 -Start -Profile $LogProfile
}

# Run secnetperf on the server.
Write-Output "Starting secnetperf server..."
$Job = Invoke-Command -Session $Session -ScriptBlock {
    C:\_work\secnetperf\artifacts\bin\windows\x64_Release_schannel\secnetperf.exe -exec:maxtput
} -AsJob

# Wait for the server to start.
Write-Output "Waiting for server to start..."
Start-Sleep -Seconds 10

# Run secnetperf on the client.
Write-Output "Running tests on the client..."

####################################################################################################

    # TEST EXECUTION

####################################################################################################

# TODO:
.\artifacts\bin\windows\x64_Release_schannel\secnetperf.exe -target:netperf-peer -exec:maxtput -test:tput -upload:10000 -timed:1

####################################################################################################

    # END TEST EXECUTION

####################################################################################################


if ($LogProfile -ne "" -and $LogProfile -ne "NULL") {
    Write-Output "Stopping logging..."
    .\msquic\scripts\log.ps1 -Stop -OutputPath .\artifacts\logs\quic
}
#Get-Content .\artifacts\logs\quic.log

function Wait-ForRemote {
    param ($Job, $ErrorAction = "Stop")
    # Ping side-channel socket on 9999 to tell the app to die
    $Socket = New-Object System.Net.Sockets.UDPClient
    $BytesToSend = @(
        0x57, 0xe6, 0x15, 0xff, 0x26, 0x4f, 0x0e, 0x57,
        0x88, 0xab, 0x07, 0x96, 0xb2, 0x58, 0xd1, 0x1c
    )
    for ($i = 0; $i -lt 120; $i++) {
        $Socket.Send($BytesToSend, $BytesToSend.Length, $RemoteAddress, 9999) | Out-Null
        $Completed = Wait-Job -Job $Job -Timeout 1
        if ($null -ne $Completed) {
            break;
        }
    }

    Stop-Job -Job $Job | Out-Null
    $RetVal = Receive-Job -Job $Job -ErrorAction $ErrorAction
    return $RetVal -join "`n"
}

# Kill the server process.
Write-Output Wait-ForRemote $Job

# Save the test results.
Write-Output "Saving test results..."

# Save as a .sql file
$FileName = "test-results-$plat-$os-$arch-$tls.sql"

Set-Content -Path $FileName -Value $SQL

} finally {
    # TODO: Do any further book keeping here.
}
