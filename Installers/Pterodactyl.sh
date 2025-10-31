#!/bin/bash

# Pterodactyl Installer with curl dependency check
# Detects Linux distribution and installs curl if needed

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to detect the OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        OS="redhat"
        VERSION=$(rpm -q --queryformat '%{VERSION}' centos-release 2>/dev/null || echo "unknown")
    elif [ -f /etc/debian_version ]; then
        OS="debian" # Fallback, /etc/os-release should be primary
        VERSION=$(cat /etc/debian_version)
    else
        OS=$(uname -s)
        VERSION=$(uname -r)
    fi
    
    print_status "Detected OS: $OS (Version: $VERSION)"
}

# Function to ensure sudo is installed on Debian
ensure_sudo_debian() {
    if [ "$OS" == "debian" ] && ! command -v sudo >/dev/null 2>&1; then
        print_warning "Sudo not found. Installing sudo..."
        apt update -y
        apt install -y sudo
        if [ $? -eq 0 ]; then
            print_status "Sudo installed successfully."
        else
            print_error "Failed to install sudo. Please install it manually."
            exit 1
        fi
    fi
}

# Function to check if curl is installed
check_curl() {
    if command -v curl >/dev/null 2>&1; then
        print_status "curl is already installed"
        return 0
    else
        print_warning "curl is not installed"
        return 1
    fi
}

# Function to install curl based on distribution
install_curl() {
    print_status "Installing curl..."
    
    case "$OS" in
    alpine)
        apk update
        apk add curl
        ;;
    arch)
        sudo pacman -Syu --noconfirm curl
        ;;
    debian | ubuntu)
        sudo apt update -y
        sudo apt install -y curl
        ;;
    fedora)
        sudo dnf update -y
        sudo dnf install -y curl
        ;;
    redhat | centos | rocky | almalinux)
        if command -v dnf >/dev/null 2>&1; then
            sudo dnf update -y
            sudo dnf install -y curl
        else
            sudo yum update -y
            sudo yum install -y curl
        fi
        ;;
    suse | opensuse*)
        sudo zypper refresh
        sudo zypper install -y curl
        ;;
    *)
        print_error "Unsupported system: $OS"
        print_error "Please install curl manually and run this script again"
        exit 1
        ;;
    esac
    
    if check_curl; then
        print_status "curl installed successfully"
    else
        print_error "Failed to install curl"
        exit 1
    fi
}

# Function to run Pterodactyl installer
run_installer() {
    print_status "Running Pterodactyl installer..."
    bash <(curl -s https://pterodactyl-installer.se)
}

# Main execution
main() {
    print_status "Starting Pterodactyl installer setup"
    
    # Check if running as root
    if [ $EUID -ne 0 ]; then
        print_error "This script must be run as root"
        exit 1
    fi
    
    # Detect OS
    detect_os
    
    # Ensure sudo is available (specifically for Debian)
    ensure_sudo_debian
    
    # Check and install curl if needed
    if ! check_curl; then
        install_curl
    fi
    
    # Run the installer
    run_installer
}

# Execute main function
main "$@"
