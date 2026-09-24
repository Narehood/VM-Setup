#!/bin/bash
set -euo pipefail

# REQUIRES_ROOT: true

SCRIPT_VERSION="1.3.0"

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
    echo -e "${CYAN}                     v${SCRIPT_VERSION}                        ${NC}"
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
VM Initial Configuration Tool v${SCRIPT_VERSION}

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
OS_VERSION=""
QUIET="false"

# cleanup unmounts only the guest-tools mount created by this process.
cleanup() {
    if [[ -n "${GUEST_TOOLS_STAGE:-}" ]]; then
        rm -rf -- "$GUEST_TOOLS_STAGE"
        GUEST_TOOLS_STAGE=""
    fi
    if [[ "$GUEST_TOOLS_MOUNTED" == true ]]; then
        if ! umount "$GUEST_TOOLS_MOUNT"; then
            print_warn "Could not unmount $GUEST_TOOLS_MOUNT; leaving it intact."
            return 0
        fi
        GUEST_TOOLS_MOUNTED=false
    fi
    if [[ -n "$GUEST_TOOLS_MOUNT" ]]; then
        rmdir -- "$GUEST_TOOLS_MOUNT" 2>/dev/null || true
    fi
}
GUEST_TOOLS_MOUNT=""
GUEST_TOOLS_MOUNTED=false
GUEST_TOOLS_STAGE=""

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
        OS_VERSION="${VERSION_ID:-unknown}"
    elif [ -f /etc/redhat-release ]; then
        OS="redhat"
        
        OS_VERSION=$(rpm -q --queryformat '%{VERSION}' centos-release 2>/dev/null)
        
        if [ -z "$OS_VERSION" ] || [ "$OS_VERSION" == "unknown" ]; then
            if [ -f /etc/redhat-release ]; then
                OS_VERSION=$(sed -nE 's/.*release[[:space:]]+([0-9]+(\.[0-9]+)?).*/\1/p' /etc/redhat-release | head -n1)
                OS_VERSION="${OS_VERSION:-unknown}"
            else
                OS_VERSION="unknown"
            fi
        fi
    elif [ -f /etc/debian_version ]; then
        OS="debian"
        OS_VERSION=$(cat /etc/debian_version)
    else
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
        OS_VERSION=$(uname -r)
    fi
    print_success "Detected: $OS ($OS_VERSION)"
}

# is_debian_based determines whether the detected OS is a Debian-family distribution (debian, ubuntu, pop, linuxmint, kali).
is_debian_based() {
    [[ "$OS" =~ ^(debian|ubuntu|pop|linuxmint|kali)$ ]]
}

# is_rhel_based checks whether the detected OS belongs to the RHEL family (fedora, redhat, centos, rocky, almalinux).
is_rhel_based() {
    [[ "$OS" =~ ^(fedora|rhel|redhat|centos|rocky|almalinux)$ ]]
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
        print_info "Using the existing Arch package database. Run a full pacman -Syu first if it is stale."
    elif is_suse_based; then
        zypper --non-interactive refresh
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
        zypper --non-interactive install "$@" || result=$?
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

# Install only the expected files from trusted ISO media, without extracting an
# arbitrary archive into /. Arch's package is in AUR, not the official repos.
install_guest_tools_archive() {
    local archive file member
    archive=$(find "$GUEST_TOOLS_MOUNT" -type f -name 'xe-guest-utilities_*_all.tgz' -print -quit)
    [[ -n "$archive" ]] || { print_error 'Generic xe-guest-utilities_*_all.tgz not found on the ISO.'; return 1; }
    GUEST_TOOLS_STAGE=$(mktemp -d "${TMPDIR:-/tmp}/vm-guest-files.XXXXXXXX") || return 1
    tar -tzf "$archive" > "$GUEST_TOOLS_STAGE/members" || return 1
    for file in usr/sbin/xe-daemon usr/sbin/xe-linux-distribution usr/bin/xenstore; do
        member=$(awk -v name="$file" '$0==name || $0=="./"name {print; exit}' "$GUEST_TOOLS_STAGE/members")
        [[ -n "$member" ]] || { print_error "Archive lacks $file"; return 1; }
        tar -xOzf "$archive" "$member" > "$GUEST_TOOLS_STAGE/$(basename "$file")" || return 1
        [[ -s "$GUEST_TOOLS_STAGE/$(basename "$file")" ]] || return 1
    done
    install -m 755 "$GUEST_TOOLS_STAGE/xe-daemon" /usr/sbin/xe-daemon || return 1
    install -m 755 "$GUEST_TOOLS_STAGE/xe-linux-distribution" /usr/sbin/xe-linux-distribution || return 1
    install -m 755 "$GUEST_TOOLS_STAGE/xenstore" /usr/bin/xenstore || return 1
    for file in read write exists rm list ls chmod watch; do
        ln -sf xenstore "/usr/bin/xenstore-$file" || return 1
    done
    # Use the installed paths; upstream ISO units may use /usr/share/oem/xs.
    cat > "$GUEST_TOOLS_STAGE/xe-linux-distribution.service" <<'EOF'
[Unit]
Description=Xen guest management agent
ConditionVirtualization=xen
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
ExecStartPre=/usr/sbin/xe-linux-distribution /var/cache/xe-linux-distribution
ExecStart=/usr/sbin/xe-daemon
[Install]
WantedBy=multi-user.target
EOF
    install -m 644 "$GUEST_TOOLS_STAGE/xe-linux-distribution.service" /etc/systemd/system/xe-linux-distribution.service || return 1
    systemctl daemon-reload || return 1
    systemctl enable --now xe-linux-distribution.service
}

# install_xcp_tools_iso mounts a guest-tools ISO attached via Xen Orchestra and runs its installer to install XCP-NG guest tools.
# Uses a private read-only mount and executes an installer only after confirmation.
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

        [[ -n "$GUEST_TOOLS_MOUNT" ]] || GUEST_TOOLS_MOUNT=$(mktemp -d "${TMPDIR:-/tmp}/vm-guest-tools.XXXXXXXX")
        print_info "Mounting $device..."

        if ! mount -o ro "$device" "$GUEST_TOOLS_MOUNT" 2>/dev/null; then
            print_error "Failed to mount ISO."
            continue
        fi

        GUEST_TOOLS_MOUNTED=true
        local script=""
        if [[ -f "$GUEST_TOOLS_MOUNT/Linux/install.sh" ]]; then
            script="$GUEST_TOOLS_MOUNT/Linux/install.sh"
        elif [[ -f "$GUEST_TOOLS_MOUNT/install.sh" ]]; then
            script="$GUEST_TOOLS_MOUNT/install.sh"
        fi

        if is_arch_based || is_suse_based; then
            if ! prompt_yes_no "Install guest utilities from trusted media $device?" n; then cleanup; return 0; fi
            if ! install_guest_tools_archive; then cleanup; return 1; fi
            print_success "XCP-NG tools installed from the generic ISO archive."
        elif [[ -n "$script" ]]; then
            print_warn "The guest-tools installer cannot be authenticated by this application."
            if ! prompt_yes_no "Execute installer from trusted media $device?" "n"; then
                cleanup
                return 1
            fi
            print_info "Running installer..."
            if (cd "$(dirname "$script")" && bash "$(basename "$script")"); then
                print_success "XCP-NG tools installed."
            else
                print_error "Guest-tools installer failed."
                cleanup
                return 1
            fi
        else
            print_error "install.sh not found on ISO."
            cleanup
            return 1
        fi

        cleanup
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

# alpine_release_branch echoes the Alpine release branch (X.Y) from OS_VERSION.
alpine_release_branch() {
    local raw="${OS_VERSION#v}"
    if [[ "$raw" =~ ^([0-9]+)\.([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
        return 0
    fi
    return 1
}

# alpine_repos_file echoes the apk repositories path (overridable for tests).
alpine_repos_file() {
    echo "${ALPINE_REPOS_FILE:-/etc/apk/repositories}"
}

# ensure_alpine_guest_tool_repos enables the matching community repo and a tagged @edge community overlay.
# xe-guest-utilities ships in community on stable releases; tagged edge is added as a safe optional overlay.
ensure_alpine_guest_tool_repos() {
    local repos branch branch_escaped main_line community_url edge_base edge_line
    local changed=0
    repos=$(alpine_repos_file)

    if [[ ! -f "$repos" ]]; then
        print_error "Alpine repositories file not found: $repos"
        return 1
    fi

    if ! branch=$(alpine_release_branch); then
        print_error "Unable to determine Alpine release branch from VERSION_ID ($OS_VERSION)."
        return 1
    fi
    branch_escaped=$(printf '%s\n' "$branch" | sed 's/\./\\./g')

    # Edit /etc/apk/repositories directly. setup-apkrepos can hang waiting for
    # interactive mirror selection even with -c, so it is intentionally avoided.

    # Uncomment a commented community line for this release branch.
    if grep -Eq "^[[:space:]]*#+.*/alpine/v${branch_escaped}/community(/|[[:space:]]|$)" "$repos"; then
        sed -i -E "s|^([[:space:]]*)#+[[:space:]]*(.*/alpine/v${branch_escaped}/community.*)|\1\2|" "$repos"
        changed=1
        print_success "Uncommented v${branch}/community repository."
    fi

    # Add community if still missing, mirroring the configured main URL when possible.
    if ! grep -Eq "^[[:space:]]*[^#].*/alpine/v${branch_escaped}/community(/|[[:space:]]|$)" "$repos"; then
        main_line=$(grep -E "^[[:space:]]*[^#].*/alpine/v${branch_escaped}/main(/|[[:space:]]|$)" "$repos" | head -n1 || true)
        if [[ -n "$main_line" ]]; then
            community_url=$(printf '%s\n' "$main_line" | sed -E 's|^[[:space:]]*||; s|/main([[:space:]].*)?$|/community|')
        else
            community_url="https://dl-cdn.alpinelinux.org/alpine/v${branch}/community"
        fi
        printf '%s\n' "$community_url" >> "$repos"
        changed=1
        print_success "Added v${branch}/community repository."
    fi

    # Add a tagged edge/community overlay (not untagged) so edge packages can be opted into safely.
    if ! grep -Eq "^[[:space:]]*@edge[[:space:]]+.*/alpine/edge/community(/|[[:space:]]|$)" "$repos"; then
        main_line=$(grep -E "^[[:space:]]*[^#].*/alpine/v${branch_escaped}/main(/|[[:space:]]|$)" "$repos" | head -n1 || true)
        if [[ -n "$main_line" ]]; then
            edge_base=$(printf '%s\n' "$main_line" | sed -E "s|^[[:space:]]*||; s|/alpine/v${branch_escaped}/main.*|/alpine|")
            edge_line="@edge ${edge_base}/edge/community"
        else
            edge_line="@edge https://dl-cdn.alpinelinux.org/alpine/edge/community"
        fi
        printf '%s\n' "$edge_line" >> "$repos"
        changed=1
        print_success "Added tagged @edge community overlay."
    else
        print_info "Tagged @edge community overlay already present."
    fi

    if ((changed)); then
        PKG_MANAGER_UPDATED="false"
    fi
    return 0
}

# install_alpine_xe_guest_utilities ensures required Alpine repos, then installs and enables xe-guest-utilities.
install_alpine_xe_guest_utilities() {
    print_info "Preparing Alpine repositories for XCP-NG guest tools..."
    ensure_alpine_guest_tool_repos || return 1

    PKG_MANAGER_UPDATED="false"
    update_repos || return 1

    if apk add xe-guest-utilities >/dev/null 2>&1; then
        print_success "Installed xe-guest-utilities from Alpine community."
    elif apk add xe-guest-utilities@edge >/dev/null 2>&1; then
        print_warn "Installed xe-guest-utilities from the tagged @edge community overlay."
    else
        print_error "xe-guest-utilities is unavailable in the configured Alpine repositories."
        print_info "Ensure v$(alpine_release_branch 2>/dev/null || echo '?')/community is enabled, then retry."
        return 1
    fi

    rc-update add xe-guest-utilities default || return 1
    /etc/init.d/xe-guest-utilities start || return 1
    print_success "XCP-NG tools installed."
    return 0
}

# --- MAIN EXECUTION ---
# When sourced (e.g. by tests), expose helpers only and skip execution.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    return 0
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_help ;;
        -v|--version) echo "v${SCRIPT_VERSION}"; exit 0 ;;
        -q|--quiet) QUIET="true"; shift ;;
        *) print_error "Unknown option: $1"; exit 1 ;;
    esac
done

show_header
check_root
trap cleanup EXIT
detect_os

if [[ "$OS" != "alpine" ]]; then
    ensure_sudo
fi

# XCP-NG Tools Installation
print_step "XCP-NG Guest Tools Configuration"
[[ "$QUIET" != "true" ]] && echo "Install XCP-NG Tools? (Recommended for VM performance)"

if prompt_yes_no "Install?" "y"; then
    update_repos

    case "$OS" in
        alpine)
            install_alpine_xe_guest_utilities || exit 1
            ;;
        arch|endeavouros|manjaro)
            install_xcp_tools_iso
            ;;
        ubuntu|pop|linuxmint)
            install_pkg xe-guest-utilities
            systemctl enable --now xe-linux-distribution.service
            print_success "XCP-NG tools installed."
            ;;
        debian)
            install_xcp_tools_iso
            ;;
        fedora|rhel|redhat|centos|rocky|almalinux)
            dnf install -y epel-release -q >/dev/null 2>&1 || true
            if ! install_pkg xe-guest-utilities && ! install_pkg xe-guest-utilities-latest; then
                install_xcp_tools_iso
            fi
            systemctl enable --now xe-linux-distribution.service
            print_success "XCP-NG tools installed."
            ;;
        suse|opensuse*|sles)
            install_xcp_tools_iso
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
print_info "Installing common utilities and download/MTU prerequisites..."
update_repos

install_result=0

if [[ "$OS" == "alpine" ]]; then
    install_pkg net-tools nano curl wget file htop ca-certificates jq coreutils iputils || install_result=$?
elif is_arch_based; then
    install_pkg net-tools btop whois curl wget file nano ca-certificates jq || install_result=$?
elif is_debian_based; then
    install_pkg net-tools btop plocate whois curl wget file nano ca-certificates jq || install_result=$?
elif is_rhel_based; then
    install_pkg net-tools curl wget file nano ca-certificates jq || install_result=$?
elif is_suse_based; then
    install_pkg net-tools curl wget file nano ca-certificates jq || install_result=$?
else
    print_warn "Unsupported system for standard tools."
    install_result=1
fi

if [[ $install_result -eq 0 ]]; then
    print_success "Utilities installed."
else
    print_error "Failed to install one or more utilities on $OS."
    exit "$install_result"
fi

# Hostname Configuration (skip for Alpine)
if [[ "$OS" != "alpine" ]]; then
    print_step "Hostname Configuration"
    [[ "$QUIET" != "true" ]] && echo -e "Current Hostname: ${CYAN}$(hostname)${NC}"

    if prompt_yes_no "Change hostname?"; then
        read -p "Enter new hostname: " new_hostname
        if [[ -z "$new_hostname" ]]; then
            print_warn "Skipped (empty input)."
        elif validate_hostname "$new_hostname"; then
            hostnamectl set-hostname "$new_hostname"
            print_success "Hostname changed to: $new_hostname"
        else
            print_error "Invalid hostname. Must be alphanumeric with optional hyphens (max 63 chars)."
        fi
    fi
fi

# Sudo User Configuration (Debian-based only, skip Alpine)
if is_debian_based; then
    print_step "User Management"

    if prompt_yes_no "Add a user to 'sudo' group?"; then
        read -p "Enter username: " user_to_add
        if [[ -z "$user_to_add" ]]; then
            print_warn "Skipped (empty input)."
        elif id "$user_to_add" &>/dev/null; then
            /usr/sbin/usermod -aG sudo "$user_to_add"
            print_success "User '$user_to_add' added to sudo group. (Log out to apply)"
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
