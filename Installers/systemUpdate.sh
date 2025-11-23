#!/bin/bash

# Function to display messages with color
print_status() {
    echo -e "\033[1;34m[INFO]\033[0m $1"
}

print_success() {
    echo -e "\033[0;32m[SUCCESS]\033[0m $1"
}

print_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1"
}

# Function to detect the OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    elif [ -f /etc/redhat-release ]; then
        OS="redhat"
    elif [ -f /etc/debian_version ]; then
        OS="debian"
    else
        OS=$(uname -s)
    fi
}

# Function to update existing packages and clean up
update_system() {
    detect_os
    print_status "Detected OS: $OS"
    print_status "Starting system update..."

    case "$OS" in
        ubuntu|debian|linuxmint|kali)
            # update: syncs repos
            # upgrade: installs newer versions
            # autoremove: removes dependencies that are no longer needed
            sudo apt update -y && \
            sudo apt upgrade -y && \
            sudo apt autoremove -y && \
            sudo apt clean
            ;;
            
        fedora|redhat|centos|rocky|almalinux)
            # --refresh: forces metadata update before the transaction
            sudo dnf upgrade --refresh -y && \
            sudo dnf autoremove -y && \
            sudo dnf clean all
            ;;
            
        arch|manjaro)
            # Arch Update Logic:
            # 1. Update Keyring first to prevent signature errors on stale VMs
            # 2. Perform full system upgrade
            # 3. Clean pacman cache (keep installed headers, remove uninstalled)
            print_status "Refreshing Arch Keyring..."
            sudo pacman -Sy --noconfirm archlinux-keyring
            
            print_status "Performing System Upgrade..."
            sudo pacman -Su --noconfirm
            
            # Optional: Clean cache (requires 'pacman-contrib' usually, so we use built-in cleaning)
            # -Sc removes packages from cache that are not currently installed
            echo "Cleaning package cache..."
            echo "y" | sudo pacman -Sc
            ;;
            
        suse|opensuse*|sles)
            sudo zypper refresh && \
            sudo zypper update -y && \
            sudo zypper clean -a
            ;;
            
        alpine)
            # Alpine uses apk. 
            # We do not use 'cache clean' as Alpine doesn't cache packages by default 
            # unless explicitly configured in /etc/apk/repositories local cache.
            sudo apk update && \
            sudo apk upgrade
            ;;
            
        *)
            print_error "Unsupported system ($OS). Exiting."
            exit 1
            ;;
    esac

    if [ $? -eq 0 ]; then
        print_success "System updated and cleaned successfully."
    else
        print_error "System update encountered errors."
        exit 1
    fi
}

# Run the update
update_system
