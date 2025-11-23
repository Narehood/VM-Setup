#!/bin/bash

# Track if we have already updated repositories to prevent redundancy
PKG_MANAGER_UPDATED="false"

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

# Function to handle package manager updates efficiently
update_repos() {
    if [ "$PKG_MANAGER_UPDATED" == "true" ]; then
        return
    fi

    echo "Updating package repositories..."
    case "$OS" in
        alpine) apk update ;;
        debian|ubuntu) sudo apt update -y ;;
        fedora) sudo dnf update -y ;;
        redhat|centos|rocky|almalinux) sudo dnf update -y ;;
        arch) sudo pacman -Sy ;;
        suse) sudo zypper refresh ;;
    esac
    PKG_MANAGER_UPDATED="true"
}

# Function to ensure sudo is installed on Debian
ensure_sudo_debian() {
    if [ "$OS" == "debian" ] && ! command -v sudo >/dev/null 2>&1; then
        echo "Sudo not found. Installing sudo..."
        apt update -y
        apt install -y sudo
        if [ $? -eq 0 ]; then
            PKG_MANAGER_UPDATED="true" # We just updated apt
            echo "Sudo installed successfully."
        else
            echo "Error: Failed to install sudo. Please install it manually."
            exit 1
        fi
    fi
}

# --- MAIN LOGIC START ---

detect_os
ensure_sudo_debian

# 1. XCP-NG Tools Installation
read -p "Would You Like To Install XCP-NG Tools? (XCP-NG Server Client) (Y/n): " install_xen_tools
install_xen_tools=${install_xen_tools:-y}

if [ "$install_xen_tools" == "y" ]; then
    update_repos

    case "$OS" in
        alpine)
            echo "https://dl-cdn.alpinelinux.org/alpine/edge/community" >>/etc/apk/repositories
            apk update
            apk add xe-guest-utilities
            rc-update add xe-guest-utilities default
            /etc/init.d/xe-guest-utilities start
            ;;
        arch)
            sudo pacman -S --noconfirm xe-guest-utilities
            ;;
        ubuntu)
            sudo apt install -y xe-guest-utilities
            ;;
        debian)
            echo "For Debian, XCP-NG tools are installed from the guest tools ISO."
            
            # SMART ISO CHECK LOOP
            while true; do
                echo "Please ensure the 'guest-tools.iso' is attached in Xen Orchestra."
                read -p "Ready to proceed? (y/n): " confirm_debian
                confirm_debian=${confirm_debian:-y}

                if [[ "$confirm_debian" =~ ^[Nn]$ ]]; then
                    echo "Skipping XCP-NG Tools installation."
                    break
                fi

                # Check if the device actually has media inserted
                # blkid returns exit code 0 if a filesystem is found (ISO inserted)
                # We check /dev/cdrom first, fallback to /dev/sr0
                DEVICE="/dev/cdrom"
                if [ ! -b "$DEVICE" ]; then DEVICE="/dev/sr0"; fi

                if sudo blkid "$DEVICE" >/dev/null 2>&1; then
                    # ISO DETECTED - PROCEED
                    
                    # Cleanup previous mounts if they exist
                    if mountpoint -q /mnt; then sudo umount /mnt; fi

                    echo "Mounting $DEVICE..."
                    if sudo mount "$DEVICE" /mnt; then
                        INSTALL_SCRIPT="/mnt/Linux/install.sh"
                        
                        if [ -f "$INSTALL_SCRIPT" ]; then
                            echo "Running installer..."
                            (cd "/mnt/Linux" && sudo bash install.sh)
                        elif [ -f "/mnt/install.sh" ]; then
                            (cd "/mnt" && sudo bash install.sh)
                        else
                            echo "Error: install.sh not found on mounted ISO."
                        fi
                        
                        sudo umount /mnt
                        break # Exit the loop after successful run
                    else
                        echo "Error: Detected ISO but failed to mount."
                    fi
                else
                    # NO ISO DETECTED
                    echo -e "\033[0;31mNo ISO detected in $DEVICE.\033[0m"
                    echo "Please go to Xen Orchestra -> VM -> Console -> Insert Guest Tools ISO."
                    echo "Pressing 'y' above will retry the detection."
                fi
            done
            ;;
        fedora|redhat|centos|rocky|almalinux)
            sudo dnf install -y epel-release
            if ! sudo dnf install -y xe-guest-utilities; then
                sudo dnf install -y xe-guest-utilities-latest
            fi
            systemctl enable --now xe-linux-distribution.service
            ;;
        suse)
            sudo zypper install -y xe-guest-utilities
            ;;
        *)
            echo "Skipping XCP-NG Tools: Unsupported OS ($OS)."
            ;;
    esac
fi

# 2. Install Standard Server Tools
update_repos

case "$OS" in
    alpine)
        apk add sudo net-tools nano curl wget
        ;;
    arch)
        sudo pacman -S --noconfirm net-tools btop whois curl wget nano
        ;;
    debian|ubuntu)
        sudo apt install -y net-tools btop plocate whois curl wget nano
        ;;
    fedora|redhat|centos|rocky|almalinux)
        sudo dnf install -y net-tools btop whois curl wget nano
        ;;
    suse)
        sudo zypper install -y net-tools btop whois curl wget nano
        ;;
    *)
        echo "Unsupported system for Standard Server Tools."
        ;;
esac

# 3. Hostname Configuration
read -p "Do you want to change the hostname? (y/N): " change_hostname
change_hostname=${change_hostname:-n}

if [ "$change_hostname" == "y" ]; then
    read -p "Enter the new hostname: " new_hostname
    if [ -n "$new_hostname" ]; then
        sudo hostnamectl set-hostname "$new_hostname"
        echo "Hostname changed to $new_hostname."
    else
        echo "Skipped."
    fi
fi

# 4. Debian Sudo User Config
if [ "$OS" == "debian" ]; then
    read -p "Add a user to the sudo group? (y/N): " add_sudo_user
    add_sudo_user=${add_sudo_user:-n}

    if [ "$add_sudo_user" == "y" ]; then
        read -p "Enter username: " user_to_add
        if [ -n "$user_to_add" ]; then
            if id "$user_to_add" >/dev/null 2>&1; then
                sudo usermod -aG sudo "$user_to_add"
                echo "User '$user_to_add' added to sudo group. Relogin required."
            else
                echo "Error: User '$user_to_add' does not exist."
            fi
        fi
    fi
fi

echo "Setup complete."
