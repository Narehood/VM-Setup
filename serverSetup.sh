#/bin/sh
apt update
apt install xe-guest-utilities net-tools cockpit htop
apt upgrade -y

git clone https://github.com/Narehood/dotfiles.git
cd dotfiles
./install.sh
sh
