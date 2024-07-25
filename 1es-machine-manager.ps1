param (
    [string]$Action,
    [string]$GithubContextInput1 = "",
    [string]$GithubContextInput2 = "",
    [string]$GithubContextInput3 = "",
    [string]$GithubContextInput4 = ""
)

Write-Host "Executing action: $Action"

if ($Action -eq "Deserialize_matrix") {
    $matrix = ConvertFrom-Json $GithubContextInput1
    $remote_powershell_supported = $matrix.remote_powershell_supported
    $role = $matrix.role
    $env_str = $matrix.env_str
    echo "remote_powershell_supported=$remote_powershell_supported" >> $env:GITHUB_ENV
    echo "role=$role" >> $env:GITHUB_ENV
    echo "env_str=$env_str" >> $env:GITHUB_ENV
}

if ($Action -eq "Disable_Windows_Defender") {
    # Disable Windows defender / firewall.
    Write-Host "Disabling Windows Defender / Firewall."
    netsh.exe advfirewall set allprofiles state off
    Set-MpPreference -EnableNetworkProtection Disabled
    Set-MpPreference -DisableDatagramProcessing $True
}

if ($Action -eq "Broadcast_IP") {
    if ($isWindows -eq $false) {
        $ipAddress = ip addr | grep 'inet ' | grep '10' | awk '{print $2}' | cut -d'/' -f1
    } else {
      $ipAddress = (Get-NetIpAddress -AddressFamily IPv4).IpAddress
    }
    $headers = @{
        "secret" = $GithubContextInput1
    }
    Invoke-WebRequest -Uri "https://netperfapi.azurewebsites.net/setkeyvalue?key=$GithubContextInput2-$GithubContextInput3-ipaddress&value=$ipAddress" -Headers $headers -Method Post
}

if ($Action -eq "Poll_IP") {
    $found = $false
    $headers = @{
        "secret" = $GithubContextInput1
    }
    $uri = "https://netperfapi.azurewebsites.net/getkeyvalue?key=$GithubContextInput2-$GithubContextInput3-ipaddress"
    do {
        Write-Output "Checking for ip address..."
        try {
            $Response = Invoke-WebRequest -Uri $uri -Headers $headers
            if (!($Response.StatusCode -eq 200)) {
            throw "Failed to get ip address. Status code: $($Response.StatusCode)"
            }
            $ipAddress = $Response.Content
            Write-Output "Ip Address found: $ipAddress"
            if ($isWindows) {
            $serverIp = $ipAddress.Split(" ") | Where-Object { $_.StartsWith("10") } | Select-Object -First 1
            } else {
            $serverIp = $ipAddress
            }
            Write-Output "Server IP: $serverIp"
            $found = $true
        }
        catch {
            Write-Output "Ip Address not found: $_"
            Start-Sleep -Seconds 5
        }
    } while (-not $found)
    Write-Host "Setting netperf-peer"
    if ($isWindows) {
        "$serverIp netperf-peer" | Out-File -Encoding ASCII -Append "$env:SystemRoot\System32\drivers\etc\hosts"
        Set-Item WSMan:\localhost\Client\TrustedHosts -Value 'netperf-peer' -Force
    } else {
        echo "$serverIp netperf-peer" | sudo tee -a /etc/hosts
    }
}

if ($Action -eq "Deprecated_remote_pwsh_poll_instructions") {
    $found = $false
      do {
          $donepath = "C:\done.txt"
          Write-Output "Checking for done.txt..."
          if (Test-Path $donepath) {
            Write-Output "done.txt found"
            $found = $true
            break
          } else {
            Write-Output "done.txt not found"
          }
          $StatePath = "C:\_state"
          if (Test-Path $StatePath) {
            ls $StatePath
            # Fetch all files in the _state directory
            $files = Get-ChildItem -Path $StatePath -File
            # Find the highest lexicographically sorted file name
            $max = 0
            foreach ($file in $files) {
                $filename = $file.Name.split(".")[0]
                $num = [int]($filename -replace "[^0-9]", "")
                if ($num -gt $max) {
                    $max = $num
                }
            }
            # Check if there is a corresponding "completed" file
            $ExecuteFileExist = Test-Path "$StatePath\execute_$($max).ps1"
            $CompletedFileExist = Test-Path "$StatePath\completed_$($max).txt"
            if ($ExecuteFileExist -and !($CompletedFileExist)) {
                Write-Host "Executing $StatePath\execute_$($max).ps1"
                Invoke-Expression "$StatePath\execute_$($max).ps1"
                Write-Host "Creating $StatePath\completed_$($max).txt"
                New-Item -ItemType File -Name "completed_$($max).txt" -Path $StatePath
            } else {
                Write-Host "No outstanding script to execute... Highest order script found so far: $max"
            }
          } else {
            Write-Host "State directory not found"
          }
          Start-Sleep -Seconds 10
      } while (-not $found)
}

if ($Action -eq "Poll_client_instructions") {
    $found = $false
    $headers = @{
      "secret" = $GithubContextInput1
    }
    $url = "https://netperfapi.azurewebsites.net"
    do {
      try {
        $Response = Invoke-WebRequest -Uri "$url/getkeyvalue?key=$GithubContextInput2-$GithubContextInput3-state" -Headers $headers
        $data = $Response.Content
        if ($data -eq "done") {
          $found = $true
          break
        }
        $dataJson = ConvertFrom-Json $data
        if ($dataJson.SeqNum -lt $dataJson.Commands.Count) {
          $command = $dataJson.Commands[$dataJson.SeqNum]
          $dataJson.SeqNum++
          $dataJson = @{
            value=$dataJson
          }
          $body = $dataJson | ConvertTo-Json
          Invoke-WebRequest -Uri "$url/setkeyvalue?key=$GithubContextInput2-$GithubContextInput3-state" -Headers $headers -Method POST -Body $body -ContentType "application/json"
          Invoke-Expression "$GithubContextInput4 -Command '$command'"
          Write-Host "Data JSON: "
          $dataJson
        } else {
          Start-Sleep -Seconds 10
        }
      }
      catch {
        Write-Output "Client not done yet. Exit reason: $_"
        Start-Sleep -Seconds 30
      }
    } while (-not $found)
}

if ($Action -eq "Stop-1es-machine") {
  headers = @{
    "secret" = "$GithubContextInput1"
  }
  Invoke-WebRequest -Uri "https://netperfapi.azurewebsites.net/setkeyvalue?key=$GithubContextInput2-$GithubContextInput3-state&value=done" -Headers $headers -Method Post
}

if ($Action -eq "deprecated_stop-1es-machine-remote-pwsh") {
  $Session = New-PSSession -ComputerName netperf-peer
  Invoke-Command -Session $Session -ScriptBlock {
    New-Item -ItemType File -Name "done.txt" -Path "C:\"
  }
}
