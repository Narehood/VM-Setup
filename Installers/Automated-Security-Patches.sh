#!/bin/bash

# Function to enable automatic updates for Debian-based systems
enable_debian_updates() {
    echo "Enabling automatic updates for Debian-based system..."
    sudo apt-get update
    sudo apt-get install -y unattended-upgrades
    sudo dpkg-reconfigure --priority=low unattended-upgrades
}

# Function to enable automatic updates for Red Hat-based systems
enable_redhat_updates() {
    echo "Enabling automatic updates for Red Hat-based system..."
    sudo yum install -y dnf-automatic
    sudo systemctl enable --now dnf-automatic-install.timer
}

# Function to enable automatic updates for Arch-based systems
enable_arch_updates() {
    echo "Enabling automatic updates for Arch-based system..."
    sudo pacman -Syu --noconfirm
    sudo pacman -S --noconfirm reflector
    sudo systemctl enable --now reflector.timer
    sudo systemctl enable --now paccache.timer
}

# Function to enable automatic updates for CentOS systems
enable_centos_updates() {
    echo "Enabling automatic updates for CentOS system..."
    sudo yum install -y yum-cron
    sudo systemctl enable --now yum-cron
}

# Function to enable automatic updates for SUSE systems
enable_suse_updates() {
    echo "Enabling automatic updates for SUSE system..."
    sudo zypper install -y yast2-online-update-configuration
    sudo yast2 online_update_configuration
}

# Identify the Linux distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Cannot identify the Linux distribution."
    exit 1
fi

# Enable automatic updates based on the distribution
case "$OS" in
    ubuntu|debian)
        enable_debian_updates
        ;;
    rhel|centos|fedora)
        enable_redhat_updates
        ;;
    arch)
        enable_arch_updates
        ;;
    suse|opensuse)
        enable_suse_updates
        ;;
    *)
        echo "Unsupported Linux distribution: $OS"
        exit 1
        ;;
esac

echo "Automatic security updates have been enabled."
