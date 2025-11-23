#!/bin/bash

# --- UI & FORMATTING FUNCTIONS ---

# Define Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to display the header
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

# Track if we have already updated repositories to prevent redundancy
PKG_MANAGER_UPDATED="false"

# Function to detect the OS
detect_os() {
    print_info "Detecting Operating System..."
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
    print_success "Detected: $OS ($VERSION)"
}

# Function to handle package manager updates efficiently
update_repos() {
    if [ "$PKG_MANAGER_UPDATED" == "true" ]; then
        return
    fi

    print_info "Updating package repositories (this may take a moment)..."
    case "$OS" in
        alpine) apk update >/dev/null ;;
        debian|ubuntu) sudo apt update -y -q ;;
        fedora) sudo dnf update -y -q ;;
        redhat|centos|rocky|almalinux) sudo dnf update -y -q ;;
        arch) sudo pacman -Sy --noconfirm ;;
        suse) sudo zypper refresh ;;
    esac
    PKG_MANAGER_UPDATED="true"
    print_success "Repositories updated."
}

# Function to ensure sudo is installed on Debian
ensure_sudo_debian() {
    if [ "$OS" == "debian" ] && ! command -v sudo >/dev/null 2>&1; then
        print_warn "Sudo not found. Installing sudo..."
        apt update -y -q && apt install -y sudo -q
        if [ $? -eq 0 ]; then
            PKG_MANAGER_UPDATED="true"
            print_success "Sudo installed successfully."
        else
            print_error "Failed to install sudo. Please install it manually."
            exit 1
        fi
    fi
}

# --- MAIN EXECUTION ---

show_header
detect_os
ensure_sudo_debian

# 1. XCP-NG Tools Installation
print_step "XCP-NG Guest Tools Configuration"
echo -e "Would You Like To Install XCP-NG Tools? (Recommended for VM performance)"
read -p "Install? (Y/n): " install_xen_tools
install_xen_tools=${install_xen_tools:-y}

if [[ "$install_xen_tools" =~ ^[Yy]$ ]]; then
    update_repos

    case "$OS" in
        alpine)
            echo "https://dl-cdn.alpinelinux.org/alpine/edge/community" >>/etc/apk/repositories
            apk update >/dev/null
            apk add xe-guest-utilities >/dev/null
            rc-update add xe-guest-utilities default >/dev/null
            /etc/init.d/xe-guest-utilities start >/dev/null
            print_success "XCP-NG tools installed."
            ;;
        arch)
            sudo pacman -S --noconfirm xe-guest-utilities
            print_success "XCP-NG tools installed."
            ;;
        ubuntu)
            sudo apt install -y xe-guest-utilities -q
            print_success "XCP-NG tools installed."
            ;;
        debian)
            print_info "For Debian, tools are installed via Guest Tools ISO."
            
            # SMART ISO CHECK LOOP
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

                if sudo blkid "$DEVICE" >/dev/null 2>&1; then
                    if mountpoint -q /mnt; then sudo umount /mnt; fi
                    print_info "Mounting $DEVICE..."
                    
                    if sudo mount "$DEVICE" /mnt; then
                        INSTALL_SCRIPT="/mnt/Linux/install.sh"
                        
                        if [ -f "$INSTALL_SCRIPT" ]; then
                            print_info "Running installer..."
                            (cd "/mnt/Linux" && sudo bash install.sh)
                        elif [ -f "/mnt/install.sh" ]; then
                            (cd "/mnt" && sudo bash install.sh)
                        else
                            print_error "install.sh not found on ISO."
                        fi
                        
                        sudo umount /mnt
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
            sudo dnf install -y epel-release -q
            if ! sudo dnf install -y xe-guest-utilities -q; then
                sudo dnf install -y xe-guest-utilities-latest -q
            fi
            systemctl enable --now xe-linux-distribution.service
            print_success "XCP-NG tools installed."
            ;;
        suse)
            sudo zypper install -y xe-guest-utilities
            print_success "XCP-NG tools installed."
            ;;
        *)
            print_warn "Skipping XCP-NG Tools: Unsupported OS ($OS)."
            ;;
    esac
else
    print_info "Skipping XCP-NG Tools."
fi

# 2. Install Standard Server Tools
print_step "Standard System Utilities"
print_info "Installing: net-tools, btop, curl, wget, nano..."
update_repos

case "$OS" in
    alpine)
        apk add sudo net-tools nano curl wget >/dev/null
        ;;
    arch)
        sudo pacman -S --noconfirm net-tools btop whois curl wget nano
        ;;
    debian|ubuntu)
        sudo apt install -y net-tools btop plocate whois curl wget nano -q
        ;;
    fedora|redhat|centos|rocky|almalinux)
        sudo dnf install -y net-tools btop whois curl wget nano -q
        ;;
    suse)
        sudo zypper install -y net-tools btop whois curl wget nano
        ;;
    *)
        print_warn "Unsupported system for Standard Tools."
        ;;
esac
print_success "Utilities installed."

# 3. Hostname Configuration
print_step "Hostname Configuration"
echo -e "Current Hostname: ${CYAN}$(hostname)${NC}"
read -p "Change hostname? (y/N): " change_hostname
change_hostname=${change_hostname:-n}

if [[ "$change_hostname" =~ ^[Yy]$ ]]; then
    read -p "Enter new hostname: " new_hostname
    if [ -n "$new_hostname" ]; then
        sudo hostnamectl set-hostname "$new_hostname"
        print_success "Hostname changed to: $new_hostname"
    else
        print_warn "Skipped (empty input)."
    fi
fi

# 4. Debian Sudo User Config
if [ "$OS" == "debian" ]; then
    print_step "User Management"
    read -p "Add a user to 'sudo' group? (y/N): " add_sudo_user
    add_sudo_user=${add_sudo_user:-n}

    if [[ "$add_sudo_user" =~ ^[Yy]$ ]]; then
        read -p "Enter username: " user_to_add
        if [ -n "$user_to_add" ]; then
            if id "$user_to_add" >/dev/null 2>&1; then
                sudo usermod -aG sudo "$user_to_add"
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
