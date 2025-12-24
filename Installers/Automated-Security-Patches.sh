#!/bin/bash
set -euo pipefail

VERSION="1.1.0"

# Function to display messages
print_status() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
print_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }
print_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }
print_warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }

# Check for root or sudo access
check_privileges() {
    if [[ $EUID -ne 0 ]]; then
        if ! sudo -v 2>/dev/null; then
            print_error "This script requires root privileges."
            exit 1
        fi
    fi
}

# Backup a config file before modifying
backup_config() {
    local file="$1"
    if [[ -f "$file" ]]; then
        sudo cp "$file" "${file}.bak.$(date +%Y%m%d%H%M%S)"
        print_status "Backed up $file"
    fi
}

show_help() {
    cat << EOF
Auto-Update Enabler v${VERSION}
Usage: $(basename "$0") [OPTIONS]

Options:
    -h, --help      Show this help message
    -v, --version   Show version
    -d, --dry-run   Show what would be done without making changes

Supported distributions:
    Debian, Ubuntu, Linux Mint, Kali, Fedora, RHEL, Rocky, AlmaLinux,
    CentOS, Arch, Manjaro, Alpine, openSUSE
EOF
    exit 0
}

# 1. DEBIAN / UBUNTU / KALI
enable_debian_updates() {
    print_status "Configuring Unattended Upgrades for Debian/Ubuntu..."
    
    sudo apt-get update -q
    sudo apt-get install -y unattended-upgrades apt-listchanges

    # Write both lines in one operation
    sudo tee /etc/apt/apt.conf.d/20auto-upgrades > /dev/null << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

    print_success "Unattended upgrades enabled."
}

# 2. RHEL / FEDORA / ROCKY / ALMA
enable_redhat_updates() {
    print_status "Configuring DNF Automatic for RHEL-based systems..."
    
    sudo dnf install -y dnf-automatic

    local conf="/etc/dnf/automatic.conf"
    backup_config "$conf"
    sudo sed -i 's/^apply_updates = no/apply_updates = yes/' "$conf"

    sudo systemctl enable --now dnf-automatic.timer
    print_success "DNF Automatic enabled."
}

# 3. CENTOS (Legacy 7)
enable_centos_updates() {
    print_status "Configuring Yum Cron for CentOS..."
    sudo yum install -y yum-cron
    
    local conf="/etc/sysconfig/yum-cron"
    backup_config "$conf"
    sudo sed -i 's/^CHECK_ONLY = yes/CHECK_ONLY = no/' "$conf"
    sudo sed -i 's/^DOWNLOAD_ONLY = yes/DOWNLOAD_ONLY = no/' "$conf"
    
    sudo systemctl enable --now yum-cron
    print_success "Yum Cron enabled."
}

# 4. ARCH LINUX
enable_arch_updates() {
    print_status "Configuring Arch Linux maintenance timers..."
    
    sudo pacman -Syu --noconfirm

    if ! pacman -Q pacman-contrib &>/dev/null; then
        sudo pacman -S --noconfirm pacman-contrib
    fi

    sudo systemctl enable --now paccache.timer
    
    # Create a custom service to refresh databases
    sudo tee /etc/systemd/system/pacman-refresh.service > /dev/null << 'EOF'
[Unit]
Description=Refresh Pacman Databases

[Service]
Type=oneshot
ExecStart=/usr/bin/pacman -Syy
EOF

    sudo tee /etc/systemd/system/pacman-refresh.timer > /dev/null << 'EOF'
[Unit]
Description=Run Pacman Refresh daily

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable --now pacman-refresh.timer
    
    print_warn "Auto-install disabled for safety on rolling release."
    print_success "Arch maintenance timers active."
}

# 5. ALPINE LINUX
enable_alpine_updates() {
    print_status "Configuring Alpine Autoupgrades..."
    
    sudo tee /etc/periodic/daily/apk-upgrade > /dev/null << 'EOF'
#!/bin/sh
apk update && apk upgrade
EOF
    
    sudo chmod +x /etc/periodic/daily/apk-upgrade
    print_success "Daily upgrade cron job created."
}

# 6. SUSE / OPENSUSE
enable_suse_updates() {
    print_status "Enabling SUSE updates via Cron..."
    
    sudo tee /etc/cron.daily/suse-update > /dev/null << 'EOF'
#!/bin/bash
zypper refresh
zypper update -y
EOF

    sudo chmod +x /etc/cron.daily/suse-update
    print_success "SUSE cron job created."
}

# --- MAIN ---

DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_help ;;
        -v|--version) echo "v${VERSION}"; exit 0 ;;
        -d|--dry-run) DRY_RUN=true; shift ;;
        *) print_error "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ ! -f /etc/os-release ]]; then
    print_error "Cannot identify the Linux distribution."
    exit 1
fi

source /etc/os-release
OS="${ID:-unknown}"

if $DRY_RUN; then
    print_status "Dry run - detected OS: $OS"
    print_status "Would configure automatic updates for this system."
    exit 0
fi

check_privileges

case "$OS" in
    ubuntu|debian|linuxmint|kali|pop)
        enable_debian_updates
        ;;
    fedora|rhel|rocky|almalinux)
        enable_redhat_updates
        ;;
    centos)
        if [[ -f /etc/centos-release ]] && grep -q "7" /etc/centos-release; then
            enable_centos_updates
        else
            enable_redhat_updates
        fi
        ;;
    arch|manjaro|endeavouros)
        enable_arch_updates
        ;;
    alpine)
        enable_alpine_updates
        ;;
    opensuse*|suse|sles)
        enable_suse_updates
        ;;
    *)
        print_error "Unsupported Linux distribution: $OS"
        exit 1
        ;;
esac

echo -e "\n\033[1;32mDone.\033[0m"
