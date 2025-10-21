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
    OS="debian" # Fallback, /etc/os-release should be primary
    VERSION=$(cat /etc/debian_version)
  else
    OS=$(uname -s)
    VERSION=$(uname -r)
  fi
}

# Function to ensure sudo is installed on Debian
ensure_sudo_debian() {
  if [ "$OS" == "debian" ] && ! command -v sudo >/dev/null 2>&1; then
    echo "Sudo not found. Installing sudo..."
    apt update -y
    apt install -y sudo
    if [ $? -eq 0 ]; then
      echo "Sudo installed successfully."
    else
      echo "Error: Failed to install sudo. Please install it manually."
      exit 1
    fi
  fi
}

# Ask the user if they want to install XCP-NG Tools
read -p "Would You Like To Install XCP-NG Tools? (XCP-NG Server Client) (Y/n): " install_xen_tools
install_xen_tools=${install_xen_tools:-y}

if [ "$install_xen_tools" == "y" ]; then
  detect_os
  ensure_sudo_debian # Ensure sudo is installed before any sudo commands

  case "$OS" in
  alpine)
    echo "https://dl-cdn.alpinelinux.org/alpine/edge/community" >>/etc/apk/repositories
    apk update
    apk add sudo xe-guest-utilities
    rc-update add xe-guest-utilities default
    /etc/init.d/xe-guest-utilities start
    ;;
  arch)
    sudo pacman -Syu --noconfirm xe-guest-utilities
    ;;
  ubuntu)
    echo "Installing XCP-NG tools for Ubuntu via apt..."
    sudo apt update -y
    sudo apt install -y xe-guest-utilities
    ;;
  debian)
    echo "For Debian, XCP-NG tools are typically installed from the guest tools ISO."
    echo "Please ensure the guest-tools.iso is attached to this VM via Xen Orchestra."
    read -p "Have you attached the guest tools ISO and are ready to proceed? (Y/n): " confirm_proceed_debian
    confirm_proceed_debian=${confirm_proceed_debian:-y}

    if [ "$confirm_proceed_debian" == "y" ]; then
      # Check if /mnt is already mounted
      if mountpoint -q /mnt; then
        echo "Warning: /mnt is already a mount point. Attempting to unmount it first."
        sudo umount /mnt
        if mountpoint -q /mnt; then
          echo "Error: Could not unmount the existing /mnt. Please unmount it manually and try again."
          echo "Skipping XCP-NG tools installation for Debian."
        fi
      fi

      # Proceed only if /mnt is not (or no longer) mounted
      if ! mountpoint -q /mnt; then
        echo "Attempting to mount /dev/cdrom to /mnt..."
        sudo mount /dev/cdrom /mnt
        if [ $? -eq 0 ]; then
          echo "Successfully mounted /dev/cdrom to /mnt."

          INSTALL_PATH_LINUX="/mnt/Linux"
          INSTALL_SCRIPT_NAME="install.sh"

          if [ -d "$INSTALL_PATH_LINUX" ] && [ -f "$INSTALL_PATH_LINUX/$INSTALL_SCRIPT_NAME" ]; then
            echo "Navigating to $INSTALL_PATH_LINUX and running $INSTALL_SCRIPT_NAME..."
            (cd "$INSTALL_PATH_LINUX" && sudo bash "$INSTALL_SCRIPT_NAME")
            if [ $? -eq 0 ]; then
              echo "XCP-NG tools installation script completed successfully."
            else
              echo "XCP-NG tools installation script finished with an error."
            fi
          elif [ -f "/mnt/$INSTALL_SCRIPT_NAME" ]; then # Fallback
            echo "Found $INSTALL_SCRIPT_NAME in /mnt. Navigating and running..."
            (cd "/mnt" && sudo bash "$INSTALL_SCRIPT_NAME")
            if [ $? -eq 0 ]; then
              echo "XCP-NG tools installation script completed successfully."
            else
              echo "XCP-NG tools installation script finished with an error."
            fi
          else
            echo "Error: Could not find $INSTALL_SCRIPT_NAME in $INSTALL_PATH_LINUX or /mnt."
            echo "Please check the contents of the guest tools ISO."
          fi

          echo "Attempting to unmount /mnt..."
          sudo umount /mnt
          if [ $? -ne 0 ]; then
            echo "Warning: Failed to unmount /mnt. You may need to unmount it manually."
          fi
        else
          echo "Error: Failed to mount /dev/cdrom. Please ensure the ISO is attached and /dev/cdrom is the correct device."
          echo "Skipping XCP-NG tools installation for Debian."
        fi
      else
        # This case is hit if /mnt was mounted and couldn't be unmounted.
        echo "Skipping XCP-NG tools installation for Debian as /mnt could not be prepared."
      fi
    else
      echo "XCP-NG tools installation for Debian skipped by user."
    fi
    ;;
  fedora)
    sudo dnf update -y
    sudo dnf install -y epel-release xe-guest-utilities
    ;;
  redhat | centos | rocky | almalinux)
    sudo yum update -y
    sudo yum install -y epel-release xe-guest-utilities
    ;;
  suse)
    sudo zypper refresh
    sudo zypper install -y xe-guest-utilities
    ;;
  *)
    echo "Unsupported system for XCP-NG Tools. Exiting."
    # Consider if exit 1 is too harsh here, or if it should just skip this section.
    # For now, keeping original behavior.
    exit 1
    ;;
  esac
fi

# Install Standard Server Tools
detect_os # OS might have been detected already, but this is harmless
ensure_sudo_debian # Ensure sudo is installed before any sudo commands

case "$OS" in
alpine)
  apk update
  apk add sudo net-tools nano
  ;;
arch)
  sudo pacman -Syu --noconfirm net-tools btop whois
  ;;
debian | ubuntu)
  sudo apt update -y
  sudo apt upgrade -y
  # Check for fastfetch, if not found, use neofetch
  if command -v fastfetch >/dev/null 2>&1; then
    sudo apt install -y net-tools btop plocate whois fastfetch
  else
    echo "Fastfetch not found. Attempting to install neofetch as a fallback."
    sudo apt install -y net-tools btop plocate whois neofetch
  fi
  ;;
fedora)
  sudo dnf update -y
  sudo dnf install -y net-tools btop whois
  ;;
redhat | centos | rocky | almalinux)
  sudo yum update -y
  sudo yum install -y net-tools btop whois
  ;;
suse)
  sudo zypper refresh
  sudo zypper install -y net-tools btop whois
  ;;
*)
  echo "Unsupported system for Standard Server Tools. Exiting."
  exit 1
  ;;
esac

# Ask the user if they want to change the hostname
read -p "Do you want to change the hostname? (y/N): " change_hostname
change_hostname=${change_hostname:-n}

if [ "$change_hostname" == "y" ]; then
  read -p "Enter the new hostname: " new_hostname
  if [ -n "$new_hostname" ]; then
    sudo hostnamectl set-hostname "$new_hostname"
    echo "Hostname changed to $new_hostname."
  else
    echo "No hostname entered. Skipping hostname change."
  fi
fi

echo "Script finished."
