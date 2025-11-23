#!/bin/bash

# Function to display messages
print_status() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
print_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }
print_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

# 1. DEBIAN / UBUNTU / KALI
enable_debian_updates() {
    print_status "Configuring Unattended Upgrades for Debian/Ubuntu..."
    
    # Update and install package
    sudo apt-get update -q
    sudo apt-get install -y unattended-upgrades apt-listchanges

    # Enable the service via configuration file instead of interactive dialog
    # This creates the activation file required by apt
    echo 'APT::Periodic::Update-Package-Lists "1";' | sudo tee /etc/apt/apt.conf.d/20auto-upgrades
    echo 'APT::Periodic::Unattended-Upgrade "1";' | sudo tee -a /etc/apt/apt.conf.d/20auto-upgrades

    print_success "Unattended upgrades enabled."
}

# 2. RHEL / FEDORA / ROCKY / ALMA
enable_redhat_updates() {
    print_status "Configuring DNF Automatic for RHEL-based systems..."
    
    sudo dnf install -y dnf-automatic

    # Configure dnf-automatic to apply updates, not just download them
    # We use sed to change apply_updates = no -> yes
    sudo sed -i 's/^apply_updates = no/apply_updates = yes/' /etc/dnf/automatic.conf

    sudo systemctl enable --now dnf-automatic.timer
    print_success "DNF Automatic enabled."
}

# 3. CENTOS (Legacy 7)
enable_centos_updates() {
    print_status "Configuring Yum Cron for CentOS..."
    sudo yum install -y yum-cron
    
    # Set CHECK_ONLY to no, and DOWNLOAD_ONLY to no (so it installs)
    sudo sed -i 's/^CHECK_ONLY = yes/CHECK_ONLY = no/' /etc/sysconfig/yum-cron
    sudo sed -i 's/^DOWNLOAD_ONLY = yes/DOWNLOAD_ONLY = no/' /etc/sysconfig/yum-cron
    
    sudo systemctl enable --now yum-cron
    print_success "Yum Cron enabled."
}

# 4. ARCH LINUX
# WARNING: Arch automatic updates can break systems.
# This implementation creates a systemd timer to update the pacman database
# but leaves the actual upgrade to the user to avoid breakage, 
# OR installs 'informant' to check news before upgrading.
enable_arch_updates() {
    print_status "Configuring Arch Linux maintenance timers..."
    
    sudo pacman -Syu --noconfirm
    # Install pacman-contrib for paccache
    if ! pacman -Q pacman-contrib >/dev/null 2>&1; then
        sudo pacman -S --noconfirm pacman-contrib
    fi

    # Clean cache automatically to save disk space
    sudo systemctl enable --now paccache.timer
    
    # Note: We do NOT enable auto-installation of packages on Arch
    # as it violates the rolling release philosophy and can brick the OS.
    # Instead, we enable a timer to refresh the database so 'checkupdates' works instantly.
    
    # Create a custom service to refresh databases
    echo "[Unit]
Description=Refresh Pacman Databases

[Service]
Type=oneshot
ExecStart=/usr/bin/pacman -Sy" | sudo tee /etc/systemd/system/pacman-refresh.service

    echo "[Unit]
Description=Run Pacman Refresh daily

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target" | sudo tee /etc/systemd/system/pacman-refresh.timer

    sudo systemctl daemon-reload
    sudo systemctl enable --now pacman-refresh.timer
    
    print_success "Arch maintenance timers active. (Note: Auto-install disabled for safety)."
}

# 5. ALPINE LINUX
enable_alpine_updates() {
    print_status "Configuring Alpine Autoupgrades..."
    # Alpine doesn't have a standard "unattended-upgrades" daemon like Debian.
    # Standard practice is a cron job.
    
    echo "#!/bin/sh
apk update && apk upgrade" | sudo tee /etc/periodic/daily/apk-upgrade
    
    sudo chmod +x /etc/periodic/daily/apk-upgrade
    print_success "Daily upgrade cron job created."
}

# --- MAIN DETECTION LOGIC ---

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Cannot identify the Linux distribution."
    exit 1
fi

case "$OS" in
    ubuntu|debian|linuxmint|kali)
        enable_debian_updates
        ;;
    fedora|rhel|rocky|almalinux)
        enable_redhat_updates
        ;;
    centos)
        # Check version for CentOS 7 (yum) vs Stream 8/9 (dnf)
        if grep -q "7" /etc/centos-release; then
            enable_centos_updates
        else
            enable_redhat_updates
        fi
        ;;
    arch|manjaro)
        enable_arch_updates
        ;;
    alpine)
        enable_alpine_updates
        ;;
    suse|opensuse*)
        # SUSE Yast requires interactive config or complex XML inputs.
        # Fallback to simple zypper cron
        print_status "Enabling SUSE updates via Cron..."
        echo -e "#!/bin/bash\nzypper refresh\nzypper update -y" | sudo tee /etc/cron.daily/suse-update
        sudo chmod +x /etc/cron.daily/suse-update
        print_success "SUSE cron job created."
        ;;
    *)
        print_error "Unsupported Linux distribution: $OS"
        exit 1
        ;;
esac

echo -e "\n\033[1;32mDone.\033[0m"
