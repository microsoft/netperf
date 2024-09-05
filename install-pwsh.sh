# Update the list of packages
sudo apt-get update
# Install pre-requisite packages.
sudo apt-get install -y wget apt-transport-https software-properties-common
# Download the Microsoft repository GPG keys
wget -q https://packages.microsoft.com/config/ubuntu/$(lsb_release --release --short)/packages-microsoft-prod.deb
# Register the Microsoft repository GPG keys
sudo dpkg -i packages-microsoft-prod.deb

echo "================= Wait for dpkg to release lock ================="
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 ; do
    echo "Waiting for other software managers to finish..."
    sleep 5
done

# Update the list of products
sudo apt-get update
# Enable the "universe" repositories
sudo add-apt-repository --yes universe

# Check if PowerShell is available in the repository
if apt-cache policy powershell | grep -q "Candidate:"; then
    echo "PowerShell is available in the repository. Installing..."
    # Install PowerShell from the repository
    echo "================= Wait for dpkg to release lock ================="
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 ; do
        echo "Waiting for other software managers to finish..."
        sleep 5
    done
    sudo apt-get install -y powershell
else
    echo "PowerShell is not available in the repository. Falling back to manual installation..."

    # Ensure we have the tools for GitHub communication
    sudo apt-get install -y curl jq

    # Create a temporary directory
    tmpDir=$(mktemp -d)

    # Fetch the latest release version of PowerShell from GitHub
    latest_version=$(curl -sSL https://api.github.com/repos/PowerShell/PowerShell/releases/latest | jq -r .tag_name)

    # Download the PowerShell package file
    echo "Downloading PowerShell package..."
    downloadUrl=$(curl -sSL "https://api.github.com/repos/PowerShell/PowerShell/releases/latest" |
        jq -r '[.assets[] | select(.name | endswith("_amd64.deb")) | .browser_download_url][0]')
    curl -sSL "$downloadUrl" -o "$tmpDir/powershell.deb"

    # Download the hash file
    echo "Downloading hash file..."
    curl -sSL "https://github.com/PowerShell/PowerShell/releases/download/$latest_version/hashes.sha256" -o "$tmpDir/hashes.sha256"

    # Extract the hash for the downloaded deb file
    expected_hash=$(grep "$(basename "$downloadUrl")" "$tmpDir/hashes.sha256" | awk '{ print $1 }')

    # Calculate the hash of the downloaded file
    actual_hash=$(sha256sum "$tmpDir/powershell.deb" | awk '{ print $1 }')

    # Compare the hashes
    if [ "$expected_hash" != "$actual_hash" ]; then
        echo "Hash mismatch! Exiting."
        exit 1
    else
        echo "Hash verified. Proceeding with installation."
    fi

    # Check if the required libicu72 is installed
    if ! dpkg -s libicu72 &>/dev/null; then
        echo "libicu72 is not installed. Installing libicu72..."
        # Get required libicu file
        curl -sSL 'https://launchpad.net/ubuntu/+archive/primary/+files/libicu72_72.1-3ubuntu3_amd64.deb' -o "$tmpDir/libicu72_72.1-3ubuntu3_amd64.deb"
        sudo dpkg --force-confold -i "$tmpDir/libicu72_72.1-3ubuntu3_amd64.deb"
    else
        echo "libicu72 is already installed."
    fi

    # Install the PowerShell package
    echo "Installing PowerShell package..."
    sudo dpkg -i "$tmpDir/powershell.deb"

    # Install PowerShell from the repository
    echo "================= Wait for dpkg to release lock ================="
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 ; do
        echo "Waiting for other software managers to finish..."
        sleep 5
    done

    # Resolve missing dependencies and finish the install (if necessary)
    echo "Resolving missing dependencies..."
    sudo apt-get install -f

    # Delete the downloaded package and hash files
    echo "Cleaning up temporary files..."
    rm -r "$tmpDir"
fi
echo "PowerShell installation complete on Linux complete. Setting HAS_PWSH=true"
