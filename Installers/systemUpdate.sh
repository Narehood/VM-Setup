#!/bin/bash
set -euo pipefail

VERSION="1.3.1"
LOGFILE="/var/log/system-update.log"
LOCKFILE="/var/run/system-update.lock"
LOG_ENABLED="true"
QUIET="false"

# --- UI & FORMATTING ---

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

# print_status outputs an informational message prefixed with a blue [INFO] tag.
# In quiet mode, only logs to file (if enabled). Otherwise prints to stdout and logs.
print_status() {
    if [[ "$QUIET" == "true" ]]; then
        [[ "$LOG_ENABLED" == "true" ]] && echo -e "${BLUE}[INFO]${NC} $1" >> "$LOGFILE"
    elif [[ "$LOG_ENABLED" == "true" ]]; then
        echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOGFILE"
    else
        echo -e "${BLUE}[INFO]${NC} $1"
    fi
}

# print_success prints a success message prefixed with a green "[SUCCESS]" tag.
# In quiet mode, only logs to file (if enabled). Otherwise prints to stdout and logs.
print_success() {
    if [[ "$QUIET" == "true" ]]; then
        [[ "$LOG_ENABLED" == "true" ]] && echo -e "${GREEN}[SUCCESS]${NC} $1" >> "$LOGFILE"
    elif [[ "$LOG_ENABLED" == "true" ]]; then
        echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOGFILE"
    else
        echo -e "${GREEN}[SUCCESS]${NC} $1"
    fi
}

# print_warn prints a warning message prefixed with a yellow [WARN] tag.
# In quiet mode, only logs to file (if enabled). Otherwise prints to stdout and logs.
print_warn() {
    if [[ "$QUIET" == "true" ]]; then
        [[ "$LOG_ENABLED" == "true" ]] && echo -e "${YELLOW}[WARN]${NC} $1" >> "$LOGFILE"
    elif [[ "$LOG_ENABLED" == "true" ]]; then
        echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOGFILE"
    else
        echo -e "${YELLOW}[WARN]${NC} $1"
    fi
}

# print_error prints MESSAGE prefixed with a red "[ERROR]" tag.
# Errors always print to stderr regardless of quiet mode, and log if enabled.
print_error() {
    if [[ "$LOG_ENABLED" == "true" ]]; then
        echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOGFILE" >&2
    else
        echo -e "${RED}[ERROR]${NC} $1" >&2
    fi
}

# --- CORE LOGIC ---

OS=""
NEEDS_REBOOT="false"
DRY_RUN="false"
SKIP_REBOOT_PROMPT="false"

# show_help prints usage instructions, supported distributions, available command-line options, and exits with status 0.
show_help() {
    cat << EOF
System Update Script v${VERSION}
Usage: $(basename "$0") [OPTIONS]

Options:
    -h, --help          Show this help message
    -v, --version       Show version
    -d, --dry-run       Show what would be done without making changes
    -q, --quiet         Suppress stdout output (errors still print to stderr)
    -y, --yes           Skip reboot prompt (auto-decline)
    -l, --log FILE      Log to specified file (default: $LOGFILE)

Supported distributions:
    Debian, Ubuntu, Linux Mint, Kali, Fedora, RHEL, Rocky, AlmaLinux,
    CentOS, Arch, Manjaro, Alpine, openSUSE/SLES
EOF
    exit 0
}

# cleanup removes the lockfile specified by LOCKFILE.
cleanup() {
    rm -f "$LOCKFILE"
}

# check_root verifies the script is running as root; prints an error message and exits with status 1 if not.
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script requires root privileges. Run with sudo."
        exit 1
    fi
}

# acquire_lock creates LOCKFILE containing the current PID to prevent concurrent runs.
# If an existing lockfile references a running PID the script prints an error and exits;
# if the lockfile is stale it is removed before writing the current PID and registering
# the cleanup trap on EXIT. Verifies the write succeeded before registering the trap.
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

    if ! echo $$ > "$LOCKFILE" 2>/dev/null; then
        print_error "Failed to create lock file: $LOCKFILE"
        exit 1
    fi

    local written_pid
    written_pid=$(cat "$LOCKFILE" 2>/dev/null || echo "")
    if [[ "$written_pid" != "$$" ]]; then
        print_error "Lock file verification failed."
        exit 1
    fi

    trap cleanup EXIT
}

# detect_os sets the global OS variable to a lowercase identifier from /etc/os-release (ID), or falls back to "redhat" if /etc/redhat-release exists, "debian" if /etc/debian_version exists, or the lowercase kernel name otherwise.
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

# check_reboot_required determines whether the system requires a reboot and sets NEEDS_REBOOT="true" when a reboot is detected.
# It inspects distribution-specific indicators (supported Debian/Ubuntu family, RedHat-family, and Arch-family checks) to decide.
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
            local running installed running_prefix installed_prefix
            running=$(uname -r)
            installed=$(pacman -Q linux 2>/dev/null | awk '{print $2}' || true)

            if [[ -n "$installed" ]]; then
                running_prefix="${running%%-*}"
                installed_prefix="${installed%%-*}"
                if [[ "$running_prefix" != "$installed_prefix" ]]; then
                    NEEDS_REBOOT="true"
                fi
            fi
            ;;
    esac
}

# update_system updates installed packages using the detected OS package manager, logs start and completion to LOGFILE, and prints status messages.
# update_system respects the DRY_RUN flag (no changes when "true") and exits with status 1 for unsupported distributions.
update_system() {
    detect_os
    print_status "Detected OS: $OS"

    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "[DRY-RUN] Would update system using appropriate package manager."
        return 0
    fi

    print_status "Starting system update..."
    [[ "$LOG_ENABLED" == "true" ]] && echo "--- Update started: $(date) ---" >> "$LOGFILE"

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

    [[ "$LOG_ENABLED" == "true" ]] && echo "--- Update completed: $(date) ---" >> "$LOGFILE"
    print_success "System updated and cleaned successfully."
}

# prompt_reboot prompts the user to reboot when a reboot is required, skips prompting in non-interactive, quiet, or configured-skip modes, and initiates a reboot if the user confirms.
prompt_reboot() {
    check_reboot_required

    if [[ "$NEEDS_REBOOT" != "true" ]]; then
        return 0
    fi

    [[ "$QUIET" != "true" ]] && echo ""
    print_warn "A system reboot is recommended to apply all updates."

    if [[ "$SKIP_REBOOT_PROMPT" == "true" || "$QUIET" == "true" ]]; then
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

# validate_log_path ensures the log directory exists, creating it if necessary.
# If creation fails, disables file logging and emits a warning.
validate_log_path() {
    local log_dir
    log_dir=$(dirname "$LOGFILE")

    if [[ ! -d "$log_dir" ]]; then
        if ! mkdir -p "$log_dir" 2>/dev/null; then
            LOG_ENABLED="false"
            echo -e "${YELLOW}[WARN]${NC} Cannot create log directory '$log_dir'. File logging disabled." >&2
            return 0
        fi
    fi

    if ! touch "$LOGFILE" 2>/dev/null; then
        LOG_ENABLED="false"
        echo -e "${YELLOW}[WARN]${NC} Cannot write to log file '$LOGFILE'. File logging disabled." >&2
    fi
}

# --- MAIN ---

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_help ;;
        -v|--version) echo "v${VERSION}"; exit 0 ;;
        -d|--dry-run) DRY_RUN="true"; shift ;;
        -q|--quiet) QUIET="true"; shift ;;
        -y|--yes) SKIP_REBOOT_PROMPT="true"; shift ;;
        -l|--log)
            if [[ -z "${2:-}" ]] || [[ "$2" == -* ]]; then
                echo "Error: -l|--log requires a filename argument" >&2
                exit 1
            fi
            LOGFILE="$2"
            shift 2
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

validate_log_path
check_root
acquire_lock
update_system
prompt_reboot
