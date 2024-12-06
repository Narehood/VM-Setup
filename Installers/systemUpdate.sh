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

# Function to update the system
update_system() {
    detect_os
    case "$OS" in
        ubuntu|debian)
            sudo apt update -y
            sudo apt upgrade -y
            sudo apt install -y net-tools cockpit htop
            ;;
        redhat|centos|rocky|almalinux)
            sudo yum update -y
            sudo yum install -y net-tools cockpit htop
            ;;
        fedora)
            sudo dnf update -y
            sudo dnf install -y net-tools cockpit htop
            ;;
        arch)
            sudo pacman -Syu --noconfirm net-tools cockpit htop
            ;;
        suse)
            sudo zypper refresh
            sudo zypper install -y net-tools cockpit htop
            ;;
        alpine)
            sudo apk update
            sudo apk add net-tools cockpit htop
            ;;
        *)
            echo "Unsupported system. Exiting."
            exit 1
            ;;
    esac
}

# Update the system
update_system
