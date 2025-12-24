#!/bin/bash
set -euo pipefail

VERSION="1.1.0"
LOGFILE="/var/log/system-update.log"
LOCKFILE="/var/run/system-update.lock"

# --- UI & FORMATTING ---

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOGFILE"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOGFILE"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOGFILE"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOGFILE"; }

# --- CORE LOGIC ---

OS=""
NEEDS_REBOOT="false"
DRY_RUN="false"
SKIP_REBOOT_PROMPT="false"

show_help() {
    cat << EOF
System Update Script v${VERSION}
Usage: $(basename "$0") [OPTIONS]

Options:
    -h, --help          Show this help message
    -v, --version       Show version
    -d, --dry-run       Show what would be done without making changes
    -y, --yes           Skip reboot prompt (auto-decline)
    -l, --log FILE      Log to specified file (default: $LOGFILE)

Supported distributions:
    Debian, Ubuntu, Linux Mint, Kali, Fedora, RHEL, Rocky, AlmaLinux,
    CentOS, Arch, Manjaro, Alpine, openSUSE/SLES
EOF
    exit 0
}

cleanup() {
    rm -f "$LOCKFILE"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script requires root privileges. Run with sudo."
        exit 1
    fi
}

acquire_lock() {
    if [[ -f "$LOCKFILE" ]]; then
        local pid
        pid=$(cat "$LOCKFILE" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            print_error "Another instance is already running (PID: $pid)."
            exit 1
        fi
        print_warn "Stale lock file found, removing."
        rm -f "$LOCKFILE"
    fi
    echo $$ > "$LOCKFILE"
    trap cleanup EXIT
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS="${ID:-unknown}"
    elif [[ -f /etc/redhat-release ]]; then
        OS="redhat"
    elif [[ -f /etc/debian_version ]]; then
        OS="debian"
    else
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    fi
}

check_reboot_required() {
    case "$OS" in
        ubuntu|debian|linuxmint|kali|pop)
            [[ -f /var/run/reboot-required ]] && NEEDS_REBOOT="true"
            ;;
        fedora|redhat|centos|rocky|almalinux)
            if command -v needs-restarting &>/dev/null; then
                needs-restarting -r &>/dev/null || NEEDS_REBOOT="true"
            fi
            ;;
        arch|manjaro|endeavouros)
            local running installed
            running=$(uname -r)
            installed=$(pacman -Q linux 2>/dev/null | awk '{print $2}' || true)
            if [[ -n "$installed" ]] && [[ ! "$running" =~ ${installed%%-*} ]]; then
                NEEDS_REBOOT="true"
            fi
            ;;
    esac
}

update_system() {
    detect_os
    print_status "Detected OS: $OS"

    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "[DRY-RUN] Would update system using appropriate package manager."
        return 0
    fi

    print_status "Starting system update..."
    echo "--- Update started: $(date) ---" >> "$LOGFILE"

    case "$OS" in
        ubuntu|debian|linuxmint|kali|pop)
            apt-get update
            apt-get upgrade -y
            apt-get autoremove -y
            apt-get clean
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
            paccache -r 2>/dev/null || pacman -Sc --noconfirm
            ;;

        manjaro|endeavouros)
            print_status "Refreshing keyrings..."
            pacman -Sy --noconfirm archlinux-keyring manjaro-keyring 2>/dev/null || \
            pacman -Sy --noconfirm archlinux-keyring
            print_status "Performing system upgrade..."
            pacman -Su --noconfirm
            print_status "Cleaning package cache..."
            paccache -r 2>/dev/null || pacman -Sc --noconfirm
            ;;

        opensuse*|suse|sles)
            zypper refresh
            zypper update -y
            zypper clean -a
            ;;

        alpine)
            apk update
            apk upgrade --available
            apk cache clean 2>/dev/null || true
            ;;

        *)
            print_error "Unsupported system ($OS). Exiting."
            exit 1
            ;;
    esac

    echo "--- Update completed: $(date) ---" >> "$LOGFILE"
    print_success "System updated and cleaned successfully."
}

prompt_reboot() {
    check_reboot_required

    if [[ "$NEEDS_REBOOT" != "true" ]]; then
        return 0
    fi

    echo ""
    print_warn "A system reboot is recommended to apply all updates."

    if [[ "$SKIP_REBOOT_PROMPT" == "true" ]]; then
        print_status "Reboot prompt skipped. Please remember to reboot later."
        return 0
    fi

    if [[ ! -t 0 ]]; then
        print_status "Non-interactive mode detected. Please reboot manually."
        return 0
    fi

    local do_reboot
    read -t 30 -p "Reboot now? (y/N): " do_reboot || do_reboot="n"
    do_reboot=${do_reboot:-n}

    if [[ "$do_reboot" =~ ^[Yy]$ ]]; then
        print_status "Rebooting system..."
        reboot
    else
        print_status "Please remember to reboot later."
    fi
}

# --- MAIN ---

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_help ;;
        -v|--version) echo "v${VERSION}"; exit 0 ;;
        -d|--dry-run) DRY_RUN="true"; shift ;;
        -y|--yes) SKIP_REBOOT_PROMPT="true"; shift ;;
        -l|--log)
            LOGFILE="$2"
            shift 2
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

check_root
acquire_lock
update_system
prompt_reboot
