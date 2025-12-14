#!/bin/bash
set -euo pipefail

# --- UI & FORMATTING ---

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# --- CORE LOGIC ---

OS=""
NEEDS_REBOOT="false"

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script requires root privileges. Run with sudo."
        exit 1
    fi
}

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS="$ID"
    elif [ -f /etc/redhat-release ]; then
        OS="redhat"
    elif [ -f /etc/debian_version ]; then
        OS="debian"
    else
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    fi
}

check_reboot_required() {
    case "$OS" in
        ubuntu|debian|linuxmint|kali)
            if [ -f /var/run/reboot-required ]; then
                NEEDS_REBOOT="true"
            fi
            ;;
        fedora|redhat|centos|rocky|almalinux)
            if command -v needs-restarting >/dev/null 2>&1; then
                if needs-restarting -r >/dev/null 2>&1; then
                    NEEDS_REBOOT="false"
                else
                    NEEDS_REBOOT="true"
                fi
            fi
            ;;
        arch|manjaro)
            # Check if running kernel differs from installed kernel
            RUNNING=$(uname -r)
            INSTALLED=$(pacman -Q linux 2>/dev/null | awk '{print $2}' || true)
            if [ -n "$INSTALLED" ] && [[ ! "$RUNNING" =~ ${INSTALLED%%-*} ]]; then
                NEEDS_REBOOT="true"
            fi
            ;;
    esac
}

update_system() {
    detect_os
    print_status "Detected OS: $OS"
    print_status "Starting system update..."

    case "$OS" in
        ubuntu|debian|linuxmint|kali)
            apt update
            apt upgrade -y
            apt autoremove -y
            apt clean
            ;;

        fedora|redhat|centos|rocky|almalinux)
            dnf upgrade --refresh -y
            dnf autoremove -y
            dnf clean all
            ;;

        arch)
            print_status "Refreshing Arch keyring..."
            pacman -Sy --noconfirm archlinux-keyring

            print_status "Performing system upgrade..."
            pacman -Su --noconfirm

            print_status "Cleaning package cache..."
            pacman -Sc --noconfirm
            ;;

        manjaro)
            print_status "Refreshing Manjaro keyring..."
            pacman -Sy --noconfirm manjaro-keyring archlinux-keyring

            print_status "Performing system upgrade..."
            pacman -Su --noconfirm

            print_status "Cleaning package cache..."
            pacman -Sc --noconfirm
            ;;

        suse|opensuse*|sles)
            zypper refresh
            zypper update -y
            zypper clean -a
            ;;

        alpine)
            apk update
            apk upgrade
            ;;

        *)
            print_error "Unsupported system ($OS). Exiting."
            exit 1
            ;;
    esac

    print_success "System updated and cleaned successfully."
}

prompt_reboot() {
    check_reboot_required
    
    if [ "$NEEDS_REBOOT" == "true" ]; then
        echo ""
        print_warn "A system reboot is recommended to apply all updates."
        read -p "Reboot now? (y/N): " do_reboot
        do_reboot=${do_reboot:-n}
        
        if [[ "$do_reboot" =~ ^[Yy]$ ]]; then
            print_status "Rebooting system..."
            reboot
        else
            print_status "Please remember to reboot later."
        fi
    fi
}

# --- MAIN ---

check_root
update_system
prompt_reboot
