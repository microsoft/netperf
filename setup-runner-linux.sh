#!/bin/bash

# Accept parameters from the user.
while getopts ":i:p:u:g:l:n" opt; do
  case ${opt} in
    i )
      peerip=$OPTARG
      ;;
    p )
      password=$OPTARG
      ;;
    u )
      username=$OPTARG
      ;;
    g )
      githubtoken=$OPTARG
      ;;
    l )
      runnerlabels=$OPTARG
      ;;
    n )
      noreboot=false
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

if [[ -z "$peerip" ]]; then
  echo "PeerIP is a required parameter." 1>&2
  exit 1
fi

if [[ -z "$password" ]]; then
  echo "Password is a required parameter." 1>&2
  exit 1
fi

if [[ -z "$username" ]]; then
  echo "Username is a required parameter." 1>&2
  exit 1
fi

if [[ -z "$runnerlabels" ]]; then
  runnerlabels="azure-ex"
fi

HOME="/home/$username"
echo ">>> Using home directory to set up runner: $HOME"

# Update apt-get
echo "================= Updating apt-get. ================="
sudo apt-get update


# Installing open-ssh server
echo "================= Installing open-ssh server. ================="
sudo apt install openssh-server -y

echo "================= Configuring SSH. ================="

# Adding "Subsystem powershell /usr/bin/pwsh -sshs -NoLogo -NoProfile" to /etc/ssh/sshd_config if its not there
if grep -q "Subsystem powershell /usr/bin/pwsh -sshs -NoLogo -NoProfile" /etc/ssh/sshd_config; then
  echo "================= Subsystem powershell is already present in /etc/ssh/sshd_config. Skipping configuring SSH. ================="
else
# NOTE: Need to further investigate permissions and ideally remove the 777 chmod.
  echo "================= Adding 'Subsystem powershell /usr/bin/pwsh -sshs -NoLogo -NoProfile' to /etc/ssh/sshd_config. ================="
  echo "Subsystem powershell /usr/bin/pwsh -sshs -NoLogo -NoProfile" | sudo tee -a /etc/ssh/sshd_config
  echo ">>> installing sshpass"
  sudo apt install sshpass -y
  echo ">>> Adding new SSH key pair to netperf peer"
  ssh-keygen -t rsa -N "" -f $HOME/.ssh/id_rsa
  sudo sshpass -p $password ssh-copy-id -i $HOME/.ssh/id_rsa.pub -o StrictHostKeyChecking=no $username@$peerip
  chmod 777 $HOME/.ssh/id_rsa
  sudo systemctl restart ssh
fi

# Installing powershell 7 (NOTE: Sometimes, will have to run this again because powershell fails to install the first run. Need investigation.)
echo "================= Installing powershell 7. ================="
sudo apt-get install -y wget apt-transport-https software-properties-common
wget -q https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sleep 5
echo "================= Updating apt-get again. ================="
sudo apt-get update
echo "================= Attempting to install powershell ================="
sudo apt-get install powershell -y
echo "Powershell 7 installed. Version:"
pwsh --version

# Add peer-ip to /etc/hosts if its not there
if grep -q "$peerip" /etc/hosts; then
  echo "================= Peer-ip is already present in /etc/hosts. ================="
else
  echo "================= Adding peer-ip to /etc/hosts. ================="
  echo "$peerip netperf-peer" | sudo tee -a /etc/hosts
fi

# *Optional: Setup this VM as a Github Actions runner
if [[ -z "$githubtoken" ]]; then
  echo "================= Github Token is not provided. Skipping the setup of Github Actions runner. ================="
else
  echo "================= Installing Github Actions runner. ================="
  echo "Making actions runner directory"

  mkdir $HOME/actions-runner


  # Download the latest runner package
  curl -o $HOME/actions-runner/actions-runner-linux-x64-2.312.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.312.0/actions-runner-linux-x64-2.312.0.tar.gz

  echo "Attempting to tar the actions runner"
  tar xzf $HOME/actions-runner/actions-runner-linux-x64-2.312.0.tar.gz -C $HOME/actions-runner

  # chown the actions runner
  sudo chown -R $username $HOME/actions-runner
  # # Run the config script.
  bash $HOME/actions-runner/config.sh --url https://github.com/microsoft/netperf --token $githubtoken --labels $runnerlabels --unattended
  # # Install the runner as a service
  cd $HOME/actions-runner
  sudo ./svc.sh install
  sudo ./svc.sh start
fi

if [[ -z "$noreboot" ]]; then
  echo "================= Rebooting the VM in 5 seconds. ================="
  sleep 5
  sudo reboot
fi
