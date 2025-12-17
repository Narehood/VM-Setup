#!/bin/bash
set -euo pipefail

# --- UI & FORMATTING FUNCTIONS ---

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# show_header clears the terminal and prints a colored, branded header for the VM initial configuration tool.
show_header() {
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${CYAN}           VM INITIAL CONFIGURATION TOOL          ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo ""
}

print_step() {
    echo -e "\n${BLUE}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

# --- CORE LOGIC ---

# Ensure administrative paths are included for Debian-based systems
export PATH=$PATH:/usr/local/sbin:/usr/sbin:/sbin

PKG_MANAGER_UPDATED="false"
OS=""
VERSION=""

# cleanup unmounts /mnt if it is a mounted filesystem to ensure no stale mounts remain on exit.
cleanup() {
    if mountpoint -q /mnt 2>/dev/null; then
        sudo umount /mnt 2>/dev/null || true
    fi
}
trap cleanup EXIT

# check_root verifies the script is running as root; if not, it prints an error and exits with status 1.
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script requires root privileges. Run with sudo."
        exit 1
    fi
}

# detect_os detects the operating system and version and sets the global variables `OS` and `VERSION`.
detect_os() {
    print_info "Detecting Operating System..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS="$ID"
        VERSION="${VERSION_ID:-unknown}"
    elif [ -f /etc/redhat-release ]; then
        OS="redhat"
        VERSION=$(rpm -q --queryformat '%{VERSION}' centos-release 2>/dev/null || echo "unknown")
    elif [ -f /etc/debian_version ]; then
        OS="debian"
        VERSION=$(cat /etc/debian_version)
    else
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
        VERSION=$(uname -r)
    fi
    print_success "Detected: $OS ($VERSION)"
}

# update_repos updates package repositories for the detected OS and marks PKG_MANAGER_UPDATED to avoid running again.
update_repos() {
    if [ "$PKG_MANAGER_UPDATED" == "true" ]; then
        return
    fi

    print_info "Updating package repositories (this may take a moment)..."
    case "$OS" in
        alpine) apk update >/dev/null 2>&1 ;;
        debian|ubuntu) apt update -y -qq >/dev/null 2>&1 ;;
        fedora) dnf update -y -q >/dev/null 2>&1 ;;
        redhat|centos|rocky|almalinux) dnf update -y -q >/dev/null 2>&1 ;;
        arch) pacman -Sy --noconfirm >/dev/null 2>&1 ;;
        suse|opensuse*) zypper refresh -q >/dev/null 2>&1 ;;
        *) print_warn "Unknown OS for repo update" ;;
    esac
    PKG_MANAGER_UPDATED="true"
    print_success "Repositories updated."
}

# install_pkg installs one or more packages using the detected OS package manager and returns non-zero if no package names are given or the OS is unsupported.
install_pkg() {
    if [ $# -eq 0 ]; then
        return 1
    fi

    case "$OS" in
        alpine) apk add "$@" >/dev/null 2>&1 ;;
        arch) pacman -S --noconfirm "$@" >/dev/null 2>&1 ;;
        debian|ubuntu) apt install -y "$@" -qq >/dev/null 2>&1 ;;
        fedora|redhat|centos|rocky|almalinux) dnf install -y "$@" -q >/dev/null 2>&1 ;;
        suse|opensuse*) zypper install -y "$@" >/dev/null 2>&1 ;;
        *) print_warn "Unsupported OS for package install"; return 1 ;;
    esac
}

# ensure_sudo_debian ensures the `sudo` package is present on Debian systems; if `sudo` is missing it installs the package.
# On successful installation it sets `PKG_MANAGER_UPDATED="true"`; on failure it prints an error and exits with status 1.
ensure_sudo_debian() {
    if [ "$OS" == "debian" ] && ! command -v sudo >/dev/null 2>&1; then
        print_warn "Sudo not found. Installing sudo..."
        apt update -y -qq >/dev/null 2>&1 && apt install -y sudo -qq >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            PKG_MANAGER_UPDATED="true"
            print_success "Sudo installed successfully."
        else
            print_error "Failed to install sudo. Please install it manually."
            exit 1
        fi
    fi
}

# validate_hostname validates that a hostname is 1–63 characters long, starts and ends with an alphanumeric character, may contain hyphens in the middle, and returns 0 if valid or 1 if invalid.
validate_hostname() {
    local hostname="$1"
    if [[ "$hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
        return 0
    else
        return 1
    fi
}

# --- MAIN EXECUTION ---

show_header
check_root
detect_os
ensure_sudo_debian

# XCP-NG Tools Installation
print_step "XCP-NG Guest Tools Configuration"
echo -e "Would You Like To Install XCP-NG Tools? (Recommended for VM performance)"
read -p "Install? (Y/n): " install_xen_tools
install_xen_tools=${install_xen_tools:-y}

if [[ "$install_xen_tools" =~ ^[Yy]$ ]]; then
    update_repos

    case "$OS" in
        alpine)
            ALPINE_REPO="https://dl-cdn.alpinelinux.org/alpine/edge/community"
            if ! grep -qF "$ALPINE_REPO" /etc/apk/repositories 2>/dev/null; then
                echo "$ALPINE_REPO" >> /etc/apk/repositories
                apk update >/dev/null 2>&1
            fi
            apk add xe-guest-utilities >/dev/null 2>&1
            rc-update add xe-guest-utilities default >/dev/null 2>&1
            /etc/init.d/xe-guest-utilities start >/dev/null 2>&1
            print_success "XCP-NG tools installed."
            ;;
        arch)
            install_pkg xe-guest-utilities
            print_success "XCP-NG tools installed."
            ;;
        ubuntu)
            install_pkg xe-guest-utilities
            print_success "XCP-NG tools installed."
            ;;
        debian)
            print_info "For Debian, tools are installed via Guest Tools ISO."
            
            while true; do
                echo -e "${YELLOW}action required:${NC} Ensure 'guest-tools.iso' is attached in Xen Orchestra."
                read -p "Ready to proceed? (y/n): " confirm_debian
                confirm_debian=${confirm_debian:-y}

                if [[ "$confirm_debian" =~ ^[Nn]$ ]]; then
                    print_warn "Skipping XCP-NG Tools installation."
                    break
                fi

                DEVICE="/dev/cdrom"
                if [ ! -b "$DEVICE" ]; then DEVICE="/dev/sr0"; fi

                if blkid "$DEVICE" >/dev/null 2>&1; then
                    if mountpoint -q /mnt; then umount /mnt; fi
                    print_info "Mounting $DEVICE..."
                    
                    if mount "$DEVICE" /mnt; then
                        INSTALL_SCRIPT="/mnt/Linux/install.sh"
                        
                        if [ -f "$INSTALL_SCRIPT" ]; then
                            print_info "Running installer..."
                            (cd "/mnt/Linux" && bash install.sh)
                        elif [ -f "/mnt/install.sh" ]; then
                            (cd "/mnt" && bash install.sh)
                        else
                            print_error "install.sh not found on ISO."
                        fi
                        
                        umount /mnt
                        break 
                    else
                        print_error "Detected ISO but failed to mount."
                    fi
                else
                    print_error "No ISO detected in $DEVICE."
                    echo "Please attach the ISO in Xen Orchestra -> VM -> Console"
                fi
            done
            ;;
        fedora|redhat|centos|rocky|almalinux)
            dnf install -y epel-release -q >/dev/null 2>&1 || true
            if ! install_pkg xe-guest-utilities; then
                install_pkg xe-guest-utilities-latest || true
            fi
            systemctl enable --now xe-linux-distribution.service >/dev/null 2>&1 || true
            print_success "XCP-NG tools installed."
            ;;
        suse|opensuse*)
            install_pkg xe-guest-utilities
            print_success "XCP-NG tools installed."
            ;;
        *)
            print_warn "Skipping XCP-NG Tools: Unsupported OS ($OS)."
            ;;
    esac
else
    print_info "Skipping XCP-NG Tools."
fi

# Install Standard Server Tools
print_step "Standard System Utilities"
print_info "Installing: net-tools, btop, curl, wget, file, nano..."
update_repos

case "$OS" in
    alpine)
        install_pkg sudo net-tools nano curl wget file
        ;;
    arch)
        install_pkg net-tools btop whois curl wget nano
        ;;
    debian|ubuntu)
        install_pkg net-tools btop plocate whois curl wget nano
        ;;
    fedora|redhat|centos|rocky|almalinux)
        install_pkg net-tools btop whois curl wget nano
        ;;
    suse|opensuse*)
        install_pkg net-tools btop whois curl wget nano
        ;;
    *)
        print_warn "Unsupported system for Standard Tools."
        ;;
esac
print_success "Utilities installed."

# Hostname Configuration
print_step "Hostname Configuration"
echo -e "Current Hostname: ${CYAN}$(hostname)${NC}"
read -p "Change hostname? (y/N): " change_hostname
change_hostname=${change_hostname:-n}

if [[ "$change_hostname" =~ ^[Yy]$ ]]; then
    read -p "Enter new hostname: " new_hostname
    if [ -n "$new_hostname" ]; then
        if validate_hostname "$new_hostname"; then
            hostnamectl set-hostname "$new_hostname"
            print_success "Hostname changed to: $new_hostname"
        else
            print_error "Invalid hostname format. Must be alphanumeric with optional hyphens (max 63 chars)."
        fi
    else
        print_warn "Skipped (empty input)."
    fi
fi

# Debian Sudo User Config
if [ "$OS" == "debian" ]; then
    print_step "User Management"
    read -p "Add a user to 'sudo' group? (y/N): " add_sudo_user
    add_sudo_user=${add_sudo_user:-n}

    if [[ "$add_sudo_user" =~ ^[Yy]$ ]]; then
        read -p "Enter username: " user_to_add
        if [ -n "$user_to_add" ]; then
            if id "$user_to_add" >/dev/null 2>&1; then
                # Explicit path used for usermod to handle Debian pathing issues
                /usr/sbin/usermod -aG sudo "$user_to_add"
                print_success "User '$user_to_add' added to sudo group. (Log out to apply)"
            else
                print_error "User '$user_to_add' does not exist."
            fi
        fi
    fi
fi

echo ""
echo -e "${BLUE}==================================================${NC}"
echo -e "${GREEN}             SETUP COMPLETE                       ${NC}"
echo -e "${BLUE}==================================================${NC}"
echo ""
