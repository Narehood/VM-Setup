#!/bin/bash

# Ask the user if they are using XCP-NG
read -p "Do you want to install XCP-NG Tools? (y/n): " install_xen_tools
if [ "$install_xen_tools" == "y" ]; then

# Check if the system is Debian, Ubuntu, Red Hat, Arch, or SUSE based
if [ -f /etc/debian_version ]; then
    # Debian-based system (including Ubuntu)
    sudo apt update -y
    sudo apt upgrade -y
    sudo apt install -y xe-guest-utilities
elif [ -f /etc/redhat-release ]; then
    # Red Hat-based system (including Fedora)
    sudo yum update -y
    sudo yum install -y xe-guest-utilities
    sudo dnf update -y
    sudo dnf install -y xe-guest-utilities
elif [ -f /etc/arch-release ]; then
    # Arch-based system
    sudo pacman -Syu --noconfirm xe-guest-utilities
elif [ -f /etc/SuSE-release ]; then
    # SUSE-based system
    sudo zypper refresh
    sudo zypper install -y xe-guest-utilities
else
    echo "Unsupported system. Exiting."
    exit 1
fi

# Install Standard Server Tools
    
fi

# Check if the system is Debian, Ubuntu, Red Hat, Arch, or SUSE based
if [ -f /etc/debian_version ]; then
    # Debian-based system (including Ubuntu)
    sudo apt update -y
    sudo apt upgrade -y
    sudo apt install -y net-tools cockpit htop
elif [ -f /etc/redhat-release ]; then
    # Red Hat-based system (including Fedora)
    sudo yum update -y
    sudo yum install -y net-tools cockpit htop
    sudo dnf update -y
    sudo dnf install -y net-tools cockpit htop
elif [ -f /etc/arch-release ]; then
    # Arch-based system
    sudo pacman -Syu --noconfirm net-tools cockpit htop
elif [ -f /etc/SuSE-release ]; then
    # SUSE-based system
    sudo zypper refresh
    sudo zypper install -y net-tools cockpit htop
else
    echo "Unsupported system. Exiting."
    exit 1
fi

# Ask the user if they want to change the hostname
read -p "Do you want to change the hostname? (y/n): " change_hostname
if [ "$change_hostname" == "y" ]; then
    read -p "Enter the new hostname: " new_hostname
    sudo hostnamectl set-hostname "$new_hostname"
    echo "Hostname changed to $new_hostname."
fi

# Clone the dotfiles repository
git clone https://github.com/Narehood/dotfiles.git
cd dotfiles
# Run the install.sh script
bash install.sh
su
su
cd
