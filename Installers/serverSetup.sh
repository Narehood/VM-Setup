#!/bin/bash
set -euo pipefail

VERSION="1.2.1"

# --- UI & FORMATTING FUNCTIONS ---

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# show_header clears the screen and prints a colored, formatted header showing the tool name and current version.
show_header() {
    [[ "$QUIET" == "true" ]] && return
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${CYAN}           VM INITIAL CONFIGURATION TOOL          ${NC}"
    echo -e "${CYAN}                     v${VERSION}                        ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo ""
}

# print_step prints a formatted step message prefixed with a blue "[STEP]" tag and a leading blank line, using the first argument as the message.
print_step() {
    [[ "$QUIET" == "true" ]] && return
    echo -e "\n${BLUE}[STEP]${NC} $1"
}

# print_success prints MESSAGE prefixed with a green [OK] indicator to stdout.
print_success() {
    [[ "$QUIET" == "true" ]] && return
    echo -e "${GREEN}[OK]${NC} $1"
}

# print_warn prints a warning message prefixed with `[WARN]` (yellow) and echoes it to stdout.
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# print_error prints an error message prefixed with `[ERROR]` in red and resets terminal color.
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# print_info prints an informational message prefixed with `[INFO]` in cyan color to stdout.
print_info() {
    [[ "$QUIET" == "true" ]] && return
    echo -e "${CYAN}[INFO]${NC} $1"
}

# show_help prints usage information, supported distributions, and exits the script.
show_help() {
    cat << EOF
VM Initial Configuration Tool v${VERSION}

Usage: $(basename "$0") [OPTIONS]

Options:
    -h, --help      Show this help message
    -v, --version   Show version
    -q, --quiet     Suppress non-essential output (warnings/errors still shown)

Supported distributions:
    Alpine, Arch, EndeavourOS, Manjaro, Debian, Ubuntu, Pop!_OS,
    Linux Mint, Fedora, RHEL, CentOS, Rocky, AlmaLinux, openSUSE/SLES
EOF
    exit 0
}

# --- CORE LOGIC ---

export PATH=$PATH:/usr/local/sbin:/usr/sbin:/sbin

PKG_MANAGER_UPDATED="false"
OS=""
VERSION_ID=""
QUIET="false"

# cleanup unmounts /mnt if it is a mount point.
cleanup() {
    if mountpoint -q /mnt 2>/dev/null; then
        umount /mnt 2>/dev/null || true
    fi
}
trap cleanup EXIT

# check_root ensures the script is running as root and exits with an error message if not.
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script requires root privileges. Run with sudo."
        exit 1
    fi
}

# detect_os detects the current operating system and sets the global variables `OS` and `VERSION_ID`.
# It prefers values from `/etc/os-release`, falls back to distribution-specific files or `uname` when necessary, and prints the detected values.
detect_os() {
    print_info "Detecting Operating System..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS="$ID"
        VERSION="${VERSION_ID:-unknown}"
    elif [ -f /etc/redhat-release ]; then
        OS="redhat"
        
        VERSION=$(rpm -q --queryformat '%{VERSION}' centos-release 2>/dev/null)
        
        if [ -z "$VERSION" ] || [ "$VERSION" == "unknown" ]; then
            if [ -f /etc/redhat-release ]; then
                VERSION=$(grep -oP '(?:release\s+)\K[\d.]+' /etc/redhat-release | cut -d. -f1-2)
                VERSION="${VERSION:-unknown}"
            else
                VERSION="unknown"
            fi
        fi
    elif [ -f /etc/debian_version ]; then
        OS="debian"
        VERSION=$(cat /etc/debian_version)
    else
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
        VERSION=$(uname -r)
    fi
    print_success "Detected: $OS ($VERSION)"
}

# is_debian_based determines whether the detected OS is a Debian-family distribution (debian, ubuntu, pop, linuxmint, kali).
is_debian_based() {
    [[ "$OS" =~ ^(debian|ubuntu|pop|linuxmint|kali)$ ]]
}

# is_rhel_based checks whether the detected OS belongs to the RHEL family (fedora, redhat, centos, rocky, almalinux).
is_rhel_based() {
    [[ "$OS" =~ ^(fedora|redhat|centos|rocky|almalinux)$ ]]
}

# is_arch_based reports whether the detected OS is an Arch-family distribution (arch, endeavouros, or manjaro).
is_arch_based() {
    [[ "$OS" =~ ^(arch|endeavouros|manjaro)$ ]]
}

# is_suse_based checks whether the current OS belongs to the SUSE family ("suse", "opensuse..." or "sles").
is_suse_based() {
    [[ "$OS" =~ ^(suse|opensuse.*|sles)$ ]]
}

# update_repos updates package repositories for the detected OS if they haven't been updated yet.
update_repos() {
    if [[ "$PKG_MANAGER_UPDATED" == "true" ]]; then
        return
    fi

    print_info "Updating package repositories..."

    if [[ "$OS" == "alpine" ]]; then
        apk update >/dev/null 2>&1
    elif is_debian_based; then
        apt-get update -qq >/dev/null 2>&1
    elif is_rhel_based; then
        dnf makecache -q >/dev/null 2>&1
    elif is_arch_based; then
        pacman -Sy --noconfirm >/dev/null 2>&1
    elif is_suse_based; then
        zypper refresh -q >/dev/null 2>&1
    else
        print_warn "Unknown OS for repo update"
        return 1
    fi

    PKG_MANAGER_UPDATED="true"
    print_success "Repositories updated."
}

# install_pkg installs one or more packages using the detected distribution's package manager and returns a non-zero status if installation fails or no package names are provided.
install_pkg() {
    if [[ $# -eq 0 ]]; then
        return 1
    fi

    local result=0

    if [[ "$OS" == "alpine" ]]; then
        apk add --quiet "$@" >/dev/null 2>&1 || result=$?
    elif is_arch_based; then
        pacman -S --noconfirm --needed "$@" >/dev/null 2>&1 || result=$?
    elif is_debian_based; then
        apt-get install -y -qq "$@" >/dev/null 2>&1 || result=$?
    elif is_rhel_based; then
        dnf install -y -q "$@" >/dev/null 2>&1 || result=$?
    elif is_suse_based; then
        zypper install -y -q "$@" >/dev/null 2>&1 || result=$?
    else
        print_warn "Unsupported OS for package install"
        return 1
    fi

    return $result
}

# ensure_sudo ensures sudo is installed on the system; if missing, it attempts installation via the detected distribution's package manager and, on success, sets PKG_MANAGER_UPDATED="true", otherwise prints an error and exits with status 1.
ensure_sudo() {
    if ! command -v sudo &>/dev/null; then
        print_warn "Sudo not found. Installing..."
        update_repos
        install_pkg sudo

        if command -v sudo &>/dev/null; then
            PKG_MANAGER_UPDATED="true"
            print_success "Sudo installed."
        else
            print_error "Failed to install sudo."
            exit 1
        fi
    fi
}

# validate_hostname validates that a hostname consists of 1–63 characters, starts and ends with an alphanumeric character, and may contain hyphens between characters.
validate_hostname() {
    local hostname="$1"
    [[ "$hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]
}

# install_xcp_tools_iso mounts a guest-tools ISO attached via Xen Orchestra and runs its installer to install XCP-NG guest tools.
# Prompts the user to confirm ISO attachment, mounts the ISO at /mnt, looks for an `install.sh` under `/mnt/Linux` or `/mnt`, executes it if found, and unmounts when finished (can be skipped by the user).
install_xcp_tools_iso() {
    print_info "Installing XCP-NG tools from Guest Tools ISO..."

    while true; do
        echo -e "${YELLOW}Action required:${NC} Ensure 'guest-tools.iso' is attached in Xen Orchestra."
        read -p "Ready to proceed? (y/n): " confirm
        confirm=${confirm:-y}

        if [[ "$confirm" =~ ^[Nn]$ ]]; then
            print_warn "Skipping XCP-NG Tools installation."
            return
        fi

        local device="/dev/cdrom"
        [[ -b "$device" ]] || device="/dev/sr0"

        if ! blkid "$device" &>/dev/null; then
            print_error "No ISO detected at $device."
            echo "Please attach the ISO in Xen Orchestra -> VM -> Console"
            continue
        fi

        mountpoint -q /mnt && umount /mnt
        print_info "Mounting $device..."

        if ! mount "$device" /mnt 2>/dev/null; then
            print_error "Failed to mount ISO."
            continue
        fi

        local script=""
        if [[ -f "/mnt/Linux/install.sh" ]]; then
            script="/mnt/Linux/install.sh"
        elif [[ -f "/mnt/install.sh" ]]; then
            script="/mnt/install.sh"
        fi

        if [[ -n "$script" ]]; then
            print_info "Running installer..."
            (cd "$(dirname "$script")" && bash "$(basename "$script")")
            print_success "XCP-NG tools installed."
        else
            print_error "install.sh not found on ISO."
        fi

        umount /mnt
        break
    done
}

# prompt_yes_no prompts the user with a yes/no question, accepts an optional default ('y' or 'n') as the second argument, and returns success (exit code 0) when the answer is yes.
prompt_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local result

    if [[ "$default" =~ ^[Yy] ]]; then
        read -p "$prompt (Y/n): " result
        result=${result:-y}
    else
        read -p "$prompt (y/N): " result
        result=${result:-n}
    fi

    [[ "$result" =~ ^[Yy]$ ]]
}

# add_user_to_sudo_group adds a user to the appropriate sudo group based on the OS (wheel for Alpine/RHEL, sudo for Debian-based).
add_user_to_sudo_group() {
    local username="$1"
    
    if [[ "$OS" == "alpine" ]]; then
        addgroup "$username" wheel
    elif is_rhel_based; then
        /usr/sbin/usermod -aG wheel "$username"
    else
        /usr/sbin/usermod -aG sudo "$username"
    fi
}

# get_sudo_group_name returns the appropriate sudo group name for the current OS.
get_sudo_group_name() {
    if [[ "$OS" == "alpine" ]] || is_rhel_based; then
        echo "wheel"
    else
        echo "sudo"
    fi
}

# user_exists checks if a user exists on the system (works on both Alpine and other distros).
user_exists() {
    local username="$1"
    if [[ "$OS" == "alpine" ]]; then
        getent passwd "$username" >/dev/null 2>&1
    else
        id "$username" &>/dev/null
    fi
}

# --- MAIN EXECUTION ---

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_help ;;
        -v|--version) echo "v${VERSION}"; exit 0 ;;
        -q|--quiet) QUIET="true"; shift ;;
        *) print_error "Unknown option: $1"; exit 1 ;;
    esac
done

show_header
check_root
detect_os
ensure_sudo

# XCP-NG Tools Installation
print_step "XCP-NG Guest Tools Configuration"
[[ "$QUIET" != "true" ]] && echo "Install XCP-NG Tools? (Recommended for VM performance)"

if prompt_yes_no "Install?" "y"; then
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
        arch|endeavouros|manjaro)
            install_pkg xe-guest-utilities
            print_success "XCP-NG tools installed."
            ;;
        ubuntu|pop|linuxmint)
            install_pkg xe-guest-utilities
            print_success "XCP-NG tools installed."
            ;;
        debian)
            install_xcp_tools_iso
            ;;
        fedora|redhat|centos|rocky|almalinux)
            dnf install -y epel-release -q >/dev/null 2>&1 || true
            install_pkg xe-guest-utilities || install_pkg xe-guest-utilities-latest || true
            systemctl enable --now xe-linux-distribution.service >/dev/null 2>&1 || true
            print_success "XCP-NG tools installed."
            ;;
        suse|opensuse*|sles)
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

install_result=0

if [[ "$OS" == "alpine" ]]; then
    install_pkg sudo net-tools nano curl wget file htop || install_result=$?
elif is_arch_based; then
    install_pkg net-tools btop whois curl wget nano || install_result=$?
elif is_debian_based; then
    install_pkg net-tools btop plocate whois curl wget nano || install_result=$?
elif is_rhel_based; then
    install_pkg net-tools btop whois curl wget nano || install_result=$?
elif is_suse_based; then
    install_pkg net-tools btop whois curl wget nano || install_result=$?
else
    print_warn "Unsupported system for standard tools."
    install_result=1
fi

if [[ $install_result -eq 0 ]]; then
    print_success "Utilities installed."
else
    print_error "Failed to install one or more utilities on $OS."
fi

# Hostname Configuration
print_step "Hostname Configuration"
[[ "$QUIET" != "true" ]] && echo -e "Current Hostname: ${CYAN}$(hostname)${NC}"

if prompt_yes_no "Change hostname?"; then
    read -p "Enter new hostname: " new_hostname
    if [[ -z "$new_hostname" ]]; then
        print_warn "Skipped (empty input)."
    elif validate_hostname "$new_hostname"; then
        if [[ "$OS" == "alpine" ]]; then
            echo "$new_hostname" > /etc/hostname
            hostname "$new_hostname"
        else
            hostnamectl set-hostname "$new_hostname"
        fi
        print_success "Hostname changed to: $new_hostname"
    else
        print_error "Invalid hostname. Must be alphanumeric with optional hyphens (max 63 chars)."
    fi
fi

# Sudo User Configuration (Debian-based and Alpine)
if is_debian_based || [[ "$OS" == "alpine" ]]; then
    print_step "User Management"
    
    local_sudo_group=$(get_sudo_group_name)

    if prompt_yes_no "Add a user to '$local_sudo_group' group?"; then
        read -p "Enter username: " user_to_add
        if [[ -z "$user_to_add" ]]; then
            print_warn "Skipped (empty input)."
        elif user_exists "$user_to_add"; then
            add_user_to_sudo_group "$user_to_add"
            print_success "User '$user_to_add' added to $local_sudo_group group. (Log out to apply)"
        else
            print_error "User '$user_to_add' does not exist."
        fi
    fi
fi

if [[ "$QUIET" != "true" ]]; then
    echo ""
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${GREEN}               SETUP COMPLETE                     ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo ""
fi
