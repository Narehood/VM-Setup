#!/bin/bash
set -euo pipefail

VERSION="1.0.0"

# --- UI & FORMATTING FUNCTIONS ---

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
NC='\033[0m'

QUIET="false"
OS=""
VERSION_ID=""
PRIMARY_IFACE=""

# show_header prints a colorized header banner with the tool name and version unless QUIET is true.
show_header() {
    [[ "$QUIET" == "true" ]] && return
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${CYAN}              MTU CONFIGURATION TOOL              ${NC}"
    echo -e "${CYAN}                     v${VERSION}                        ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo ""
}

# print_step prints a step header message prefixed with "[STEP]" in blue to stdout unless QUIET is true.
print_step() {
    [[ "$QUIET" == "true" ]] && return
    echo -e "\n${BLUE}[STEP]${NC} $1"
}

# print_success prints a green "[OK]" success message followed by the provided text unless QUIET is true.
print_success() {
    [[ "$QUIET" == "true" ]] && return
    echo -e "${GREEN}[OK]${NC} $1"
}

# print_warn prints a yellow `[WARN]`-prefixed warning message to stdout using the provided text.
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# print_error prints an error message prefixed with [ERROR] in red and echoes the provided message.
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# print_info prints an informational message prefixed with "[INFO]" in cyan unless QUIET is true.
print_info() {
    [[ "$QUIET" == "true" ]] && return
    echo -e "${CYAN}[INFO]${NC} $1"
}

# show_help prints the usage, available options, a brief description of the MTU Configuration Tool, and the list of supported distributions, then exits with status 0.
show_help() {
    cat << EOF
MTU Configuration Tool v${VERSION}

Usage: $(basename "$0") [OPTIONS]

Options:
    -h, --help      Show this help message
    -v, --version   Show version
    -q, --quiet     Suppress non-essential output (warnings/errors still shown)

Description:
    Configures MTU settings for network interfaces and Docker to resolve
    packet fragmentation issues common in virtualized environments (XCP-NG,
    OVH vRack, etc.).

Supported distributions:
    Alpine, Arch, EndeavourOS, Manjaro, Debian, Ubuntu, Pop!_OS,
    Linux Mint, Fedora, RHEL, CentOS, Rocky, AlmaLinux, openSUSE/SLES
EOF
    exit 0
}

# --- CORE LOGIC ---

export PATH=$PATH:/usr/local/sbin:/usr/sbin:/sbin

# check_root verifies the script is running as root and exits with status 1 after printing an error message if not.
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script requires root privileges. Run with sudo."
        exit 1
    fi
}

# detect_os detects the current operating system and version and sets the global variables `OS` and `VERSION_ID`. It prefers `/etc/os-release`, falls back to distro-specific release files, and finally to `uname` if needed; it also prints status messages.
detect_os() {
    print_info "Detecting Operating System..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS="$ID"
        VERSION_ID="${VERSION_ID:-unknown}"
    elif [ -f /etc/redhat-release ]; then
        OS="redhat"
        VERSION_ID=$(grep -oP '(?:release\s+)\K[\d.]+' /etc/redhat-release | cut -d. -f1-2)
        VERSION_ID="${VERSION_ID:-unknown}"
    elif [ -f /etc/debian_version ]; then
        OS="debian"
        VERSION_ID=$(cat /etc/debian_version)
    else
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
        VERSION_ID=$(uname -r)
    fi
    print_success "Detected: $OS ($VERSION_ID)"
}

# is_debian_based returns true if the detected OS is Debian, Ubuntu, Pop, Linux Mint, or Kali.
is_debian_based() {
    [[ "$OS" =~ ^(debian|ubuntu|pop|linuxmint|kali)$ ]]
}

# is_rhel_based determines whether the detected OS is a RHEL-family distribution (fedora, redhat, centos, rocky, almalinux).
is_rhel_based() {
    [[ "$OS" =~ ^(fedora|redhat|centos|rocky|almalinux)$ ]]
}

# is_arch_based returns true if the detected OS is Arch Linux, EndeavourOS, or Manjaro.
is_arch_based() {
    [[ "$OS" =~ ^(arch|endeavouros|manjaro)$ ]]
}

# is_suse_based tests whether OS indicates a SUSE-family distribution (matches `suse`, `opensuse*`, or `sles`).
is_suse_based() {
    [[ "$OS" =~ ^(suse|opensuse.*|sles)$ ]]
}

# detect_primary_interface detects the system's primary network interface and sets the global PRIMARY_IFACE variable.
# It prefers the interface from the default route, falls back to the first non-loopback/non-virtual interface, prints the detected interface and its current MTU, and exits with status 1 if no interface can be determined.
detect_primary_interface() {
    print_info "Detecting primary network interface..."

    PRIMARY_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

    if [[ -z "$PRIMARY_IFACE" ]]; then
        PRIMARY_IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -vE '^(lo|docker|veth|br-)' | head -n1)
    fi

    if [[ -z "$PRIMARY_IFACE" ]]; then
        print_error "Could not detect primary network interface."
        exit 1
    fi

    local current_mtu
    current_mtu=$(ip link show "$PRIMARY_IFACE" | grep -oP 'mtu \K\d+')
    print_success "Detected: $PRIMARY_IFACE (current MTU: $current_mtu)"
}

# escape_regex escapes regex metacharacters in a string for safe use in sed/grep.
escape_regex() {
    printf '%s\n' "$1" | sed 's/[][.*^$/\\]/\\&/g'
}

# prompt_yes_no prompts the user with a yes/no question and exits with status 0 when the answer is yes and non-zero otherwise.
# prompt_yes_no takes two arguments: a prompt string and an optional default ('y' or 'n', default is 'n'); the default controls the displayed choice and the value used when the user presses Enter.
prompt_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local result

    if [[ "$default" =~ ^[Yy] ]]; then
        read -r -p "$prompt (Y/n): " result
        result=${result:-y}
    else
        read -r -p "$prompt (y/N): " result
        result=${result:-n}
    fi

    [[ "$result" =~ ^[Yy]$ ]]
}

# validate_mtu validates that an MTU value is an integer between 68 and 9000 (inclusive).
validate_mtu() {
    local mtu="$1"
    if [[ "$mtu" =~ ^[0-9]+$ ]] && [[ "$mtu" -ge 68 ]] && [[ "$mtu" -le 9000 ]]; then
        return 0
    fi
    return 1
}

# apply_mtu_immediate applies the given MTU to the specified network interface immediately and reports success or failure.
apply_mtu_immediate() {
    local iface="$1"
    local mtu="$2"

    if ip link set dev "$iface" mtu "$mtu" 2>/dev/null; then
        print_success "Applied MTU $mtu to $iface"
        return 0
    else
        print_error "Failed to apply MTU to $iface"
        return 1
    fi
}

# apply_mtu_persistent configures a persistent MTU for the specified network interface using the distribution's preferred mechanism and returns non‑zero if persistent configuration is unsupported.
apply_mtu_persistent() {
    local iface="$1"
    local mtu="$2"

    print_info "Configuring persistent MTU for $iface..."

    if [[ "$OS" == "alpine" ]]; then
        apply_mtu_alpine "$iface" "$mtu"
    elif is_debian_based; then
        apply_mtu_debian "$iface" "$mtu"
    elif is_rhel_based; then
        apply_mtu_rhel "$iface" "$mtu"
    elif is_arch_based; then
        apply_mtu_arch "$iface" "$mtu"
    elif is_suse_based; then
        apply_mtu_suse "$iface" "$mtu"
    else
        print_warn "Unsupported OS for persistent MTU configuration."
        print_info "MTU applied to current session only."
        return 1
    fi
}

# apply_mtu_debian adds or updates /etc/network/interfaces to persistently set the MTU for a given network interface by inserting a `post-up ip link set dev <iface> mtu <mtu>` stanza and creates a basic interfaces file if it does not exist.
apply_mtu_debian() {
    local iface="$1"
    local mtu="$2"
    local iface_escaped
    local interfaces_file="/etc/network/interfaces"
    local post_up_cmd="post-up ip link set dev $iface mtu $mtu"

    iface_escaped=$(escape_regex "$iface")

    if [[ ! -f "$interfaces_file" ]]; then
        print_warn "$interfaces_file not found. Creating basic configuration."
        cat > "$interfaces_file" << EOF
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

auto $iface
iface $iface inet dhcp
    $post_up_cmd
EOF
        print_success "Created $interfaces_file with MTU configuration."
        return 0
    fi

    sed -i "/post-up ip link set dev $iface_escaped mtu/d" "$interfaces_file"

    if grep -qE "^iface $iface_escaped" "$interfaces_file"; then
        sed -i "/^iface $iface_escaped/a\\    $post_up_cmd" "$interfaces_file"
        print_success "Updated $interfaces_file with MTU $mtu for $iface"
    else
        cat >> "$interfaces_file" << EOF

auto $iface
iface $iface inet dhcp
    $post_up_cmd
EOF
        print_success "Added $iface configuration to $interfaces_file"
    fi
}

# apply_mtu_alpine updates Alpine's /etc/network/interfaces to persistently set the MTU for the specified network interface.
# It inserts a `post-up ip link set dev <iface> mtu <mtu>` line for the interface, removing any existing matching post-up entries first.
# Returns 0 on success, 1 if /etc/network/interfaces is missing or the interface is not present in the file.
apply_mtu_alpine() {
    local iface="$1"
    local mtu="$2"
    local esc_iface
    local interfaces_file="/etc/network/interfaces"

    esc_iface=$(escape_regex "$iface")

    if [[ ! -f "$interfaces_file" ]]; then
        print_warn "$interfaces_file not found."
        return 1
    fi

    sed -i "/post-up ip link set dev $esc_iface mtu/d" "$interfaces_file"

    if grep -qE "^iface $esc_iface" "$interfaces_file"; then
        sed -i "/^iface $esc_iface/a\\    post-up ip link set dev $iface mtu $mtu" "$interfaces_file"
        print_success "Updated $interfaces_file with MTU $mtu"
    else
        print_warn "Interface $iface not found in $interfaces_file"
        return 1
    fi
}

# apply_mtu_rhel configures the persistent MTU for an interface on RHEL-family systems, preferring NetworkManager (nmcli) when available and falling back to updating /etc/sysconfig/network-scripts/ifcfg-<iface>.
apply_mtu_rhel() {
    local iface="$1"
    local mtu="$2"

    if command -v nmcli &>/dev/null; then
        local conn_name
        conn_name=$(nmcli -t -f NAME,DEVICE con show | grep ":$iface$" | cut -d: -f1 | head -n1)

        if [[ -n "$conn_name" ]]; then
            nmcli con mod "$conn_name" 802-3-ethernet.mtu "$mtu" 2>/dev/null
            print_success "Configured MTU $mtu via NetworkManager for $conn_name"
            return 0
        fi
    fi

    local ifcfg_file="/etc/sysconfig/network-scripts/ifcfg-$iface"
    if [[ -f "$ifcfg_file" ]]; then
        sed -i '/^MTU=/d' "$ifcfg_file"
        echo "MTU=$mtu" >> "$ifcfg_file"
        print_success "Updated $ifcfg_file with MTU $mtu"
    else
        print_warn "Could not configure persistent MTU for $iface"
        return 1
    fi
}

# apply_mtu_arch applies a persistent MTU for the specified network interface on Arch-based systems.
# If NetworkManager is available and a connection is associated with the interface, it sets the MTU on that connection;
# otherwise it creates a systemd-networkd `.link` file under /etc/systemd/network to set MTUBytes for the interface.
# iface - network interface name (e.g., eth0)
# mtu - MTU value (integer)
apply_mtu_arch() {
    local iface="$1"
    local mtu="$2"

    if command -v nmcli &>/dev/null; then
        local conn_name
        conn_name=$(nmcli -t -f NAME,DEVICE con show | grep ":$iface$" | cut -d: -f1 | head -n1)

        if [[ -n "$conn_name" ]]; then
            nmcli con mod "$conn_name" 802-3-ethernet.mtu "$mtu" 2>/dev/null
            print_success "Configured MTU $mtu via NetworkManager"
            return 0
        fi
    fi

    local networkd_dir="/etc/systemd/network"
    mkdir -p "$networkd_dir"

    cat > "$networkd_dir/10-$iface.link" << EOF
[Match]
OriginalName=$iface

[Link]
MTUBytes=$mtu
EOF
    print_success "Created systemd-networkd configuration for $iface"
}

# apply_mtu_suse sets the MTU for a SUSE network interface by updating or appending `MTU=<value>` in `/etc/sysconfig/network/ifcfg-<iface>`, prints a success message on update, and returns non-zero with a warning if the ifcfg file is missing.
apply_mtu_suse() {
    local iface="$1"
    local mtu="$2"
    local ifcfg_file="/etc/sysconfig/network/ifcfg-$iface"

    if [[ -f "$ifcfg_file" ]]; then
        sed -i '/^MTU=/d' "$ifcfg_file"
        echo "MTU=$mtu" >> "$ifcfg_file"
        print_success "Updated $ifcfg_file with MTU $mtu"
    else
        print_warn "Could not find $ifcfg_file"
        return 1
    fi
}

# reset_mtu_config resets MTU configuration for the given network interface and sets the interface MTU to 1500 immediately.
# It also removes persistent MTU entries from distribution-specific configuration (Debian/Alpine /etc/network/interfaces, RHEL ifcfg or NetworkManager, Arch systemd .link, SUSE ifcfg) so the interface uses the default MTU after reboot.
reset_mtu_config() {
    local iface="$1"
    local escaped_iface

    print_info "Resetting MTU configuration for $iface..."

    apply_mtu_immediate "$iface" 1500

    if [[ "$OS" == "alpine" ]] || is_debian_based; then
        local interfaces_file="/etc/network/interfaces"
        escaped_iface=$(escape_regex "$iface")
        if [[ -f "$interfaces_file" ]]; then
            sed -i "/post-up ip link set dev $escaped_iface mtu/d" "$interfaces_file"
            print_success "Removed MTU configuration from $interfaces_file"
        fi
    elif is_rhel_based; then
        if command -v nmcli &>/dev/null; then
            local conn_name
            conn_name=$(nmcli -t -f NAME,DEVICE con show | grep ":$iface$" | cut -d: -f1 | head -n1)
            if [[ -n "$conn_name" ]]; then
                nmcli con mod "$conn_name" 802-3-ethernet.mtu "" 2>/dev/null || true
            fi
        fi
        local ifcfg_file="/etc/sysconfig/network-scripts/ifcfg-$iface"
        if [[ -f "$ifcfg_file" ]]; then
            sed -i '/^MTU=/d' "$ifcfg_file"
        fi
        print_success "Reset MTU configuration"
    elif is_arch_based; then
        rm -f "/etc/systemd/network/10-$iface.link" 2>/dev/null || true
        print_success "Removed systemd-networkd MTU configuration"
    elif is_suse_based; then
        local ifcfg_file="/etc/sysconfig/network/ifcfg-$iface"
        if [[ -f "$ifcfg_file" ]]; then
            sed -i '/^MTU=/d' "$ifcfg_file"
        fi
        print_success "Reset MTU configuration"
    fi
}

# update_docker_json updates or creates the Docker daemon.json file at the given path to set the top-level `mtu` value to the provided numeric MTU, preserving file permissions and ownership when possible.
update_docker_json() {
    local daemon_json="$1"
    local mtu="$2"
    local tmp_file
    tmp_file=$(mktemp)

    if command -v jq &>/dev/null && [[ -f "$daemon_json" ]] && [[ -s "$daemon_json" ]]; then
        jq --arg mtu "$mtu" '.mtu = ($mtu | tonumber)' "$daemon_json" > "$tmp_file" 2>/dev/null || {
            sed "s/\"mtu\": *[0-9]\+/\"mtu\": $mtu/; t; s/}/\"mtu\": $mtu\n}/" "$daemon_json" > "$tmp_file"
        }
    else
        echo "{\"mtu\": $mtu}" > "$tmp_file"
    fi

    chmod --reference="$daemon_json" "$tmp_file" 2>/dev/null || chmod 644 "$tmp_file"
    chown --reference="$daemon_json" "$tmp_file" 2>/dev/null || true

    mv "$tmp_file" "$daemon_json"
}

# configure_docker_mtu configures Docker's daemon.json with the given MTU, applies that MTU to existing Docker bridge interfaces, and optionally prompts to restart the Docker service.
# mtu is the numeric MTU value to write into /etc/docker/daemon.json and to apply to Docker bridge interfaces.
configure_docker_mtu() {
    local mtu="$1"

    if ! command -v docker &>/dev/null; then
        print_info "Docker not installed, skipping Docker MTU configuration."
        return 0
    fi

    print_info "Configuring Docker MTU..."

    local daemon_json="/etc/docker/daemon.json"
    local docker_dir="/etc/docker"

    mkdir -p "$docker_dir"
    [[ -f "$daemon_json" ]] || echo "{}" > "$daemon_json"

    update_docker_json "$daemon_json" "$mtu"
    print_success "Updated $daemon_json with MTU $mtu"

    apply_docker_bridges_mtu "$mtu"

    if prompt_yes_no "Restart Docker service to apply changes?" "y"; then
        if systemctl restart docker 2>/dev/null; then
            print_success "Docker service restarted."
        else
            print_warn "Failed to restart Docker. Please restart manually."
        fi
    else
        print_info "Remember to restart Docker for changes to take effect."
    fi
}

# apply_docker_bridges_mtu applies the given MTU value to any existing Docker bridge interfaces.
# It prints success or warning messages for each bridge and does nothing if no Docker bridges are found.
apply_docker_bridges_mtu() {
    local mtu="$1"

    print_info "Applying MTU to existing Docker bridges..."

    local bridges
    bridges=$(ip -o link show type bridge | awk -F': ' '{print $2}' | grep -E '^(docker|br-)' || true)

    if [[ -z "$bridges" ]]; then
        print_info "No Docker bridges found."
        return 0
    fi

    for bridge in $bridges; do
        if ip link set dev "$bridge" mtu "$mtu" 2>/dev/null; then
            print_success "Applied MTU $mtu to $bridge"
        else
            print_warn "Failed to apply MTU to $bridge"
        fi
    done
}

# reset_docker_mtu removes any `mtu` setting from /etc/docker/daemon.json (if present), preserves the file's permissions and ownership where possible, prints status messages, and resets existing Docker bridge interfaces to MTU 1500.
reset_docker_mtu() {
    local daemon_json="/etc/docker/daemon.json"

    if [[ ! -f "$daemon_json" ]]; then
        print_info "No Docker daemon.json found."
        return 0
    fi

    local tmp_file
    tmp_file=$(mktemp)

    if command -v jq &>/dev/null && [[ -s "$daemon_json" ]]; then
        jq 'del(.mtu)' "$daemon_json" > "$tmp_file" 2>/dev/null || {
            sed '/\"mtu\"/d' "$daemon_json" > "$tmp_file"
        }
    else
        sed '/\"mtu\"/d' "$daemon_json" > "$tmp_file"
    fi

    chmod --reference="$daemon_json" "$tmp_file" 2>/dev/null || chmod 644 "$tmp_file"
    chown --reference="$daemon_json" "$tmp_file" 2>/dev/null || true

    mv "$tmp_file" "$daemon_json"
    print_success "Removed MTU from Docker configuration"

    apply_docker_bridges_mtu 1500
}

# test_mtu_size checks if the specified MTU can reach 1.1.1.1 by pinging with ICMP packets sized to MTU-28.
# Returns 0 if the ping succeeds, 1 otherwise.
test_mtu_size() {
    local mtu="$1"
    local target="1.1.1.1"
    local packet_size=$((mtu - 28))

    if ping -c 2 -M do -s "$packet_size" "$target" &>/dev/null; then
        return 0
    fi
    return 1
}

# test_mtu_values tests connectivity to 1.1.1.1 using a sequence of MTU sizes and offers the last successful MTU for application.
# 
# Runs ICMP tests for MTU values (1500,1450,1400,1350,1300,1250,1200,1150,1100), reports OK/FAIL for each, and tracks the highest tested size that succeeds.
# If at least one size succeeds, prompts the user to apply the recommended MTU; on confirmation, echoes the chosen MTU to stdout and returns 0.
# If no sizes succeed or the user declines, prints a warning/info and returns 1.
test_mtu_values() {
    print_step "Testing MTU Values"
    echo ""
    print_info "Testing connectivity to 1.1.1.1 with various MTU sizes..."
    print_info "This may take a moment..."
    echo ""

    local test_sizes=(1500 1450 1400 1350 1300 1250 1200 1150 1100)
    local last_working=0

    for size in "${test_sizes[@]}"; do
        printf "  Testing MTU %d... " "$size"
        if test_mtu_size "$size"; then
            echo -e "${GREEN}✓ OK${NC}"
            last_working=$size
        else
            echo -e "${RED}✗ FAIL${NC}"
            [[ $last_working -eq 0 ]] && break
        fi
    done

    echo ""
    if [[ $last_working -gt 0 ]]; then
        echo -e "${GREEN}Recommendation: Use MTU ${last_working}${NC}"
        echo ""
        if prompt_yes_no "Apply MTU $last_working to your system?" "y"; then
            echo "$last_working"
            return 0
        fi
    else
        print_warn "Could not determine optimal MTU. System may not support ICMP ping."
        print_info "Using default menu instead."
        return 1
    fi

    return 1
}

# show_mtu_menu displays an interactive MTU selection menu, validates user input, and echoes the chosen MTU value or the string "reset".
show_mtu_menu() {
    {
        echo ""
        echo -e "${CYAN}Select MTU Value:${NC}"
        echo ""
        echo "  1) 1500  - Default (standard networks)"
        echo "  2) 1450  - Some Virtualized environments"
        echo "  3) 1350  - OVH vRack w/ PfSense and XCP-NG"
        echo "  4) Custom value"
        echo "  5) Test MTU values (ping)"
        echo "  6) Reset to default"
        echo ""
    } >&2

    read -r -p "Selection [1-6]: " choice >&2

    case "$choice" in
        1) echo "1500" ;;
        2) echo "1450" ;;
        3) echo "1350" ;;
        4)
            read -r -p "Enter custom MTU (68-9000): " custom_mtu >&2
            if validate_mtu "$custom_mtu"; then
                echo "$custom_mtu"
            else
                print_error "Invalid MTU value. Must be between 68 and 9000." >&2
                exit 1
            fi
            ;;
        5)
            test_result=$(test_mtu_values)
            test_status=$?
            if [[ $test_status -eq 0 ]] && [[ -n "$test_result" ]]; then
                echo "$test_result"
            else
                show_mtu_menu
            fi
            ;;
        6) echo "reset" ;;
        *)
            print_error "Invalid selection." >&2
            exit 1
            ;;
    esac
}

# show_current_status prints a header and lists non-loopback network interfaces with their current MTU values.
show_current_status() {
    print_step "Current MTU Status"

    echo ""
    echo -e "${CYAN}Network Interfaces:${NC}"
    ip -o link show | grep -vE '^[0-9]+: lo:' || true | while read -r line; do
        local iface mtu
        iface=$(echo "$line" | awk -F': ' '{print $2}' | cut -d'@' -f1)
        mtu=$(echo "$line" | grep -oP 'mtu \K\d+')
        printf "  %-20s MTU: %s\n" "$iface" "$mtu"
    done
    echo ""
}

# --- MAIN EXECUTION ---

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_help ;;
        -v|--version) echo "v${VERSION}"; exit 0 ;;
        -q|--quiet) QUIET="true"; shift ;;
        *) print_error "Unknown option: $1"; exit 1 ;;
    esac
done

show_header
check_root
detect_os
detect_primary_interface
show_current_status

print_step "MTU Configuration"
selected_mtu=$(show_mtu_menu)

if [[ "$selected_mtu" == "reset" ]]; then
    print_step "Resetting MTU Configuration"
    reset_mtu_config "$PRIMARY_IFACE"

    if command -v docker &>/dev/null; then
        if prompt_yes_no "Reset Docker MTU configuration?" "y"; then
            reset_docker_mtu
        fi
    fi
else
    print_step "Applying MTU $selected_mtu"
    apply_mtu_immediate "$PRIMARY_IFACE" "$selected_mtu"
    apply_mtu_persistent "$PRIMARY_IFACE" "$selected_mtu"

    if command -v docker &>/dev/null; then
        echo ""
        if prompt_yes_no "Configure Docker to use MTU $selected_mtu?" "y"; then
            configure_docker_mtu "$selected_mtu"
        fi
    fi
fi

show_current_status

if [[ "$QUIET" != "true" ]]; then
    echo ""
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${GREEN}           MTU CONFIGURATION COMPLETE             ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo ""
    print_info "Changes will persist across reboots."
    echo ""
fi