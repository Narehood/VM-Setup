#!/bin/bash

# Function to detect the OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        OS="redhat"
        VERSION=$(rpm -q --queryformat '%{VERSION}' centos-release)
    elif [ -f /etc/debian_version ]; then
        OS="debian"
        VERSION=$(cat /etc/debian_version)
    else
        OS=$(uname -s)
        VERSION=$(uname -r)
    fi
}

# Ask the user if they want to install XCP-NG Tools
read -p "Would You Like To Install XCP-NG Tools? (XCP-NG Server Client) (Y/n): " install_xen_tools
install_xen_tools=${install_xen_tools:-y}

if [ "$install_xen_tools" == "y" ]; then
    detect_os
    case "$OS" in
        ubuntu|debian)
            sudo apt update -y
            sudo apt install -y xe-guest-utilities
            ;;
        redhat|centos|rocky|almalinux)
            sudo yum update -y
            sudo yum install -y epel-release xe-guest-utilities
            ;;
        fedora)
            sudo dnf update -y
            sudo dnf install -y epel-release xe-guest-utilities
            ;;
        arch)
            sudo pacman -Syu --noconfirm xe-guest-utilities
            ;;
        suse)
            sudo zypper refresh
            sudo zypper install -y xe-guest-utilities
            ;;
        alpine)
            echo "https://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories
            apk update
            apk add sudo xe-guest-utilities
            ;;
        *)
            echo "Unsupported system. Exiting."
            exit 1
            ;;
    esac
fi

# Install Standard Server Tools
detect_os

case "$OS" in
    ubuntu|debian)
        sudo apt update -y
        sudo apt upgrade -y
        sudo apt install -y net-tools btop plocate whois
        ;;
    redhat|centos|rocky|almalinux)
        sudo yum update -y
        sudo yum install -y net-tools btop whois
        ;;
    fedora)
        sudo dnf update -y
        sudo dnf install -y net-tools btop whois
        ;;
    arch)
        sudo pacman -Syu --noconfirm net-tools btop whois
        ;;
    suse)
        sudo zypper refresh
        sudo zypper install -y net-tools btop whois
        ;;
    alpine)
        apk update
        apk add sudo net-tools btop whois
        ;;
    *)
        echo "Unsupported system. Exiting."
        exit 1
        ;;
esac

# Ask the user if they want to change the hostname
read -p "Do you want to change the hostname? (y/N): " change_hostname
change_hostname=${change_hostname:-n}

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
cd
