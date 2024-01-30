# Note: Verified and tested on Azure with Ubuntu 20.04 LTS only.

# Accept parameters from the user.
while getopts ":u:p:i:g:n" opt; do
  case ${opt} in
    u )
      username=$OPTARG
      ;;
    p )
      password=$OPTARG
      ;;
    i )
      peerip=$OPTARG
      ;;
    g )
      githubtoken=$OPTARG
      ;;
    n )
      noreboot=true
      ;;
    \? )
      echo "Invalid option: -$OPTARG" 1>&2
      exit 1
      ;;
    : )
      echo "Option -$OPTARG requires an argument." 1>&2
      exit 1
      ;;
  esac
done

if [[ -z "$password" || -z "$peerip" ]]; then
  echo "Password and PeerIP are required parameters." 1>&2
  exit 1
fi

if [[ -z "$noreboot" ]]; then
  noreboot=false
fi

if [[ -z "$username" ]]; then
  username="secnetperf"
fi

# Update apt-get
echo "Updating apt-get."
sudo apt-get update


# Installing open-ssh server
echo "Installing open-ssh server."
sudo apt install openssh-server -y

# Adding "Subsystem powershell /usr/bin/pwsh -sshs -NoLogo -NoProfile" to /etc/ssh/sshd_config if its not there
if grep -q "Subsystem powershell /usr/bin/pwsh -sshs -NoLogo -NoProfile" /etc/ssh/sshd_config; then
  echo "Subsystem powershell is already present in /etc/ssh/sshd_config."
else
  echo "Adding 'Subsystem powershell /usr/bin/pwsh -sshs -NoLogo -NoProfile' to /etc/ssh/sshd_config."
  sudo echo "Subsystem powershell /usr/bin/pwsh -sshs -NoLogo -NoProfile" >> /etc/ssh/sshd_config
fi

# Installing powershell 7
echo "Installing powershell 7."
sudo apt-get install -y wget apt-transport-https software-properties-common
wget -q https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo apt-get install -y powershell
echo "Powershell 7 installed. Version:"
pwsh --version

# Add peer-ip to /etc/hosts if its not there
if grep -q "$peerip" /etc/hosts; then
  echo "Peer-ip is already present in /etc/hosts."
else
  echo "Adding peer-ip to /etc/hosts."
  sudo echo "$peerip netperf-peer" >> /etc/hosts
fi

# *Optional: Setup this VM as a Github Actions runner
if [[ -z "$githubtoken" ]]; then
  echo "Github Token is not provided. Skipping the setup of Github Actions runner."
else
  echo "Installing Github Actions runner."
fi

if [[ -z "$noreboot" ]]; then
  echo "Rebooting the VM in 5 seconds."
  sleep 5
  sudo reboot
fi
