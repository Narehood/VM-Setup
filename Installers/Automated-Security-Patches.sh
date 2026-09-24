#!/bin/bash
set -euo pipefail

# REQUIRES_ROOT: true

VERSION="1.2.0"

# print_status prints an informational message prefixed with `[INFO]` in blue to stdout.
print_status() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
# print_success prints a green "[SUCCESS]" label followed by the provided message to stdout.
print_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }
# print_error prints the given message prefixed with "[ERROR]" in red.
print_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }
# print_warn prints a yellow "[WARN]" label followed by the given message to stdout.
print_warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }

# check_privileges checks if the script is running as root or has sudo access and exits if neither is available.
check_privileges() {
    if [[ $EUID -ne 0 ]]; then
        if ! sudo -v 2>/dev/null; then
            print_error "This script requires root privileges."
            exit 1
        fi
    fi
}

run_as_root() {
    if ((EUID == 0)); then "$@"; else sudo -- "$@"; fi
}

# backup_config creates a timestamped backup of the specified file (appends .bak.YYYYMMDDHHMMSS) if the file exists.
backup_config() {
    local file="$1"
    if [[ -f "$file" ]]; then
        run_as_root cp "$file" "${file}.bak.$(date +%Y%m%d%H%M%S)"
        print_status "Backed up $file"
    fi
}

# show_help displays the script usage, supported distributions, available options (-h/--help, -v/--version, -d/--dry-run), and exits.
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

# enable_debian_updates configures Unattended Upgrades on Debian/Ubuntu systems by installing required packages and writing APT periodic update and unattended-upgrade settings to /etc/apt/apt.conf.d/20auto-upgrades.
enable_debian_updates() {
    print_status "Configuring Unattended Upgrades for Debian/Ubuntu..."
    
    run_as_root apt-get update -q
    run_as_root apt-get install -y unattended-upgrades apt-listchanges

    backup_config /etc/apt/apt.conf.d/20auto-upgrades
    # Write both lines in one operation
    run_as_root tee /etc/apt/apt.conf.d/20auto-upgrades > /dev/null << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

    run_as_root systemctl enable --now apt-daily.timer apt-daily-upgrade.timer
    print_success "Unattended upgrades enabled."
}

# enable_redhat_updates configures DNF Automatic on RHEL-based systems, enables automatic application of package updates, and starts the dnf-automatic timer service.
enable_redhat_updates() {
    print_status "Configuring DNF Automatic for RHEL-based systems..."
    
    local conf="/etc/dnf/automatic.conf"
    local timer=dnf-automatic.timer temporary
    if command -v dnf5 >/dev/null; then
        run_as_root dnf5 install -y dnf5-plugin-automatic
        timer=dnf5-automatic.timer
    else
        run_as_root dnf install -y dnf-automatic
    fi
    backup_config "$conf"
    temporary=$(mktemp)
    if [[ -f "$conf" ]]; then run_as_root cat "$conf" > "$temporary"; fi
    awk '
        /^\[/ {commands=($0=="[commands]")}
        commands && /^[[:space:]]*(apply_updates|upgrade_type)[[:space:]]*=/ {next}
        {print}
        /^\[commands\]$/ {found=1; print "apply_updates = yes\nupgrade_type = security"}
        END {if (!found) print "\n[commands]\napply_updates = yes\nupgrade_type = security"}
    ' "$temporary" | run_as_root tee "$conf" >/dev/null
    rm -f "$temporary"
    run_as_root systemctl enable --now "$timer"
    run_as_root systemctl is-active --quiet "$timer"
    print_success "DNF Automatic enabled."
}

# enable_centos_updates configures and enables yum-cron for CentOS (legacy 7).
# It installs the yum-cron package, backs up /etc/sysconfig/yum-cron, sets CHECK_ONLY and DOWNLOAD_ONLY to "no", and enables & starts the yum-cron service.
enable_centos_updates() {
    print_status "Configuring Yum Cron for CentOS..."
    run_as_root yum install -y yum-cron
    
    local conf="/etc/sysconfig/yum-cron"
    backup_config "$conf"
    run_as_root sed -i 's/^CHECK_ONLY = yes/CHECK_ONLY = no/' "$conf"
    run_as_root sed -i 's/^DOWNLOAD_ONLY = yes/DOWNLOAD_ONLY = no/' "$conf"
    
    run_as_root systemctl enable --now yum-cron
    print_success "Yum Cron enabled."
}

# enable_arch_updates configures maintenance timers without performing a surprise full upgrade.
enable_arch_updates() {
    print_status "Configuring Arch Linux maintenance timers..."

    if ! pacman -Q pacman-contrib &>/dev/null; then
        run_as_root pacman -S --noconfirm pacman-contrib
    fi

    run_as_root systemctl enable --now paccache.timer
    
    # Keep the old unit name so existing refresh timers migrate to checkupdates.
    run_as_root tee /etc/systemd/system/pacman-refresh.service > /dev/null << 'EOF'
[Unit]
Description=Check Arch updates without changing the system package database

[Service]
Type=oneshot
ExecStart=/usr/bin/checkupdates
SuccessExitStatus=2
EOF

    run_as_root tee /etc/systemd/system/pacman-refresh.timer > /dev/null << 'EOF'
[Unit]
Description=Check Arch updates daily

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

    run_as_root systemctl daemon-reload
    run_as_root systemctl enable --now pacman-refresh.timer
    
    print_warn "Auto-install disabled for safety on rolling release."
    print_success "Arch maintenance timers active."
}

# enable_alpine_updates creates a daily /etc/periodic/daily/apk-upgrade script that runs `apk update` and `apk upgrade` and makes it executable.
enable_alpine_updates() {
    print_status "Configuring Alpine Autoupgrades..."
    run_as_root mkdir -p /etc/periodic/daily
    
    run_as_root tee /etc/periodic/daily/apk-upgrade > /dev/null << 'EOF'
#!/bin/sh
apk update && apk upgrade
EOF
    
    run_as_root chmod +x /etc/periodic/daily/apk-upgrade
    run_as_root rc-update add crond default
    run_as_root rc-service crond start
    run_as_root rc-service crond status
    print_success "Daily full-package upgrade job enabled (Alpine has no security-only upgrade filter)."
}

# enable_suse_updates creates a daily cron job at /etc/cron.daily/suse-update that refreshes zypper repositories and applies available updates automatically.
enable_suse_updates() {
    print_status "Enabling SUSE updates via Cron..."
    run_as_root zypper --non-interactive install cron
    run_as_root mkdir -p /etc/cron.daily
    
    if [[ "$OS" == opensuse-tumbleweed || "$OS" == opensuse-slowroll ]]; then
        run_as_root tee /etc/cron.daily/suse-update > /dev/null << 'EOF'
#!/bin/sh
zypper --non-interactive refresh && zypper --non-interactive list-updates
EOF
        print_warn "Rolling SUSE releases: notification only. Apply complete snapshots with zypper dup."
    else
        run_as_root tee /etc/cron.daily/suse-update > /dev/null << 'EOF'
#!/bin/bash
zypper --non-interactive refresh && zypper --non-interactive patch --category security
EOF
    fi

    run_as_root chmod +x /etc/cron.daily/suse-update
    run_as_root systemctl enable --now cron.service
    run_as_root systemctl is-active --quiet cron.service
    print_success "SUSE maintenance job enabled."
}

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then return 0; fi

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
    fedora|rhel|redhat|rocky|almalinux)
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
