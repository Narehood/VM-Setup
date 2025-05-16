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
        alpine)
            echo "https://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories
            apk update
            apk add sudo xe-guest-utilities
            rc-update add xe-guest-utilities default
            /etc/init.d/xe-guest-utilities start
            ;;
        arch)
            sudo pacman -Syu --noconfirm xe-guest-utilities
            ;;
        debian|ubuntu)
            sudo apt update -y
            sudo apt install -y xe-guest-utilities
            ;;
        fedora)
            sudo dnf update -y
            sudo dnf install -y epel-release xe-guest-utilities
            ;;
        redhat|centos|rocky|almalinux)
            sudo yum update -y
            sudo yum install -y epel-release xe-guest-utilities
            ;;
        suse)
            sudo zypper refresh
            sudo zypper install -y xe-guest-utilities
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
    alpine)
        apk update
        apk add sudo net-tools nano
        ;;
    arch)
        sudo pacman -Syu --noconfirm net-tools btop whois
        ;;
    debian|ubuntu)
        sudo apt update -y
        sudo apt upgrade -y
        sudo apt install -y net-tools btop plocate whois
        ;;
    fedora)
        sudo dnf update -y
        sudo dnf install -y net-tools btop whois
        ;;
    redhat|centos|rocky|almalinux)
        sudo yum update -y
        sudo yum install -y net-tools btop whois
        ;;
    suse)
        sudo zypper refresh
        sudo zypper install -y net-tools btop whois
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

# Clone the dotfiles repository (Skip for Alpine)
if [ "$OS" != "alpine" ]; then
    git clone https://github.com/Narehood/dotfiles.git
    cd dotfiles
    bash install.sh
    cd
fi
