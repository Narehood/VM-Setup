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
    elif grep -q "Alpine Linux" /etc/os-release; then
        OS="alpine"
        VERSION=$(cat /etc/alpine-release)
    else
        OS=$(uname -s)
        VERSION=$(uname -r)
    fi
}

# Function to update existing packages only (no new installations)
update_system() {
    detect_os
    case "$OS" in
        ubuntu|debian)
            sudo apt update -y
            sudo apt upgrade -y
            ;;
        redhat|centos|rocky|almalinux)
            sudo yum update -y
            sudo yum upgrade -y
            ;;
        fedora)
            sudo dnf update -y
            sudo dnf upgrade -y
            ;;
        arch)
            sudo pacman -Syu --noconfirm
            ;;
        suse)
            sudo zypper refresh
            sudo zypper update -y
            ;;
        alpine)
            sudo apk update
            sudo apk upgrade
            ;;
        *)
            echo "Unsupported system. Exiting."
            exit 1
            ;;
    esac
}

# Update the system without installing new packages
update_system
