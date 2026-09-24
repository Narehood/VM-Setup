#!/bin/bash
set -euo pipefail

# REQUIRES_ROOT: true

VERSION="1.1.0"

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
    OVH vRack, Virtual PfSense, etc.).

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
        VERSION_ID=$(sed -nE 's/.*release[[:space:]]+([0-9]+(\.[0-9]+)?).*/\1/p' /etc/redhat-release | head -n1)
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
    [[ "$OS" =~ ^(fedora|rhel|redhat|centos|rocky|almalinux)$ ]]
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

    PRIMARY_IFACE=$(ip route | awk '$1=="default" && !found {print $5; found=1}')

    if [[ -z "$PRIMARY_IFACE" ]]; then
        PRIMARY_IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -vE '^(lo|docker|veth|br-)' | head -n1)
    fi

    if [[ -z "$PRIMARY_IFACE" ]]; then
        print_error "Could not detect primary network interface."
        exit 1
    fi

    local current_mtu
    current_mtu=$(ip link show "$PRIMARY_IFACE" | awk 'match($0, /mtu [0-9]+/) { print substr($0, RSTART + 4, RLENGTH - 4); exit }')
    print_success "Detected: $PRIMARY_IFACE (current MTU: $current_mtu)"
}

# escape_regex escapes regex metacharacters in a string for safe use in sed/grep.
escape_regex() {
    printf '%s' "$1" | sed 's/[][.*^$/\\]/\\&/g'
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
    if [[ "$mtu" =~ ^[1-9][0-9]{1,3}$ ]] && ((10#$mtu >= 68 && 10#$mtu <= 9000)); then
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

# Edit the active backend, preserving addressing and unrelated settings.
backup_network_file() {
    local backup
    backup=$(mktemp "${1}.vm-setup-backup.XXXXXXXX") || return 1
    cp -p -- "$1" "$backup" || return 1
    print_info "Backup: $backup"
}

apply_ifupdown_mtu() {
    local file="$1" iface="$2" mtu="$3" temporary
    [[ -f "$file" && ! -L "$file" ]] || return 1
    awk -v iface="$iface" '$1=="iface" && $2==iface {found=1} END {exit !found}' "$file" || return 1
    temporary=$(mktemp "${file}.XXXXXXXX") || return 1
    cp -p "$file" "$temporary" || return 1
    if ! awk -v iface="$iface" -v mtu="$mtu" '
        $1=="iface" {active=($2==iface)}
        active && ($1=="mtu" || ($1=="post-up" && $2=="ip" && $3=="link" && $4=="set" && $5=="dev" && $6==iface && $7=="mtu")) {next}
        {print}
        $1=="iface" && $2==iface {print "    mtu " mtu}
    ' "$file" > "$temporary"; then rm -f "$temporary"; return 1; fi
    backup_network_file "$file" || return 1
    mv -- "$temporary" "$file"
}

apply_netplan_mtu() {
    local iface="$1" mtu="$2" key stage temporary mac="" config_dir="${NETWORK_ROOT:-}/etc/netplan"
    command -v python3 >/dev/null || { print_error 'Netplan requires python3 and python3-yaml.'; return 1; }
    if [[ -r "${NETWORK_ROOT:-}/sys/class/net/$iface/address" ]]; then
        read -r mac < "${NETWORK_ROOT:-}/sys/class/net/$iface/address"
    fi
    # Match the existing definition; never invent a new DHCP interface.
    key=$(netplan get | python3 -c '
import sys, yaml
cfg=yaml.safe_load(sys.stdin) or {}
iface=sys.argv[1]
mac=sys.argv[2].lower()
matches=[]
for section in ("ethernets", "bonds", "bridges", "vlans", "wifis"):
    for name, data in cfg.get("network", {}).get(section, {}).items():
        match=data.get("match", {})
        if data.get("set-name")==iface or (not match and name==iface) or (match.get("name")==iface) or (mac and match.get("macaddress", "").lower()==mac):
            matches.append(section+"."+name)
if len(matches)!=1: sys.exit("Cannot uniquely match interface to Netplan; configure its MTU manually.")
print(matches[0])
' "$iface" "$mac") || return 1
    [[ "$key" =~ ^[a-z]+\.[a-zA-Z0-9_-]+$ ]] || { print_error 'Unsupported Netplan definition name.'; return 1; }
    stage=$(mktemp -d) || return 1
    mkdir -p "$stage/etc/netplan" || return 1
    cp -p "$config_dir/"*.yaml "$stage/etc/netplan/" || { rm -rf "$stage"; return 1; }
    if ! netplan set --root-dir "$stage" --origin-hint 99-vm-setup-mtu "network.$key.mtu=$mtu" || ! netplan generate --root-dir "$stage"; then
        rm -rf "$stage"; return 1
    fi
    local override="$config_dir/99-vm-setup-mtu.yaml"
    [[ ! -L "$override" ]] || { rm -rf "$stage"; return 1; }
    if [[ -f "$override" ]]; then backup_network_file "$override" || return 1; fi
    temporary=$(mktemp "${override}.XXXXXXXX") || { rm -rf "$stage"; return 1; }
    install -m 600 "$stage/etc/netplan/99-vm-setup-mtu.yaml" "$temporary" || { rm -rf "$stage"; rm -f "$temporary"; return 1; }
    mv "$temporary" "$override" || { rm -rf "$stage"; rm -f "$temporary"; return 1; }
    rm -rf "$stage"
}

apply_mtu_persistent() {
    local iface="$1" mtu="$2" uuid file network_file temporary
    [[ "$iface" =~ ^[a-zA-Z0-9_.:-]+$ ]] && validate_mtu "$mtu" || return 1
    if command -v netplan >/dev/null && compgen -G "${NETWORK_ROOT:-}/etc/netplan/*.yaml" >/dev/null; then
        apply_netplan_mtu "$iface" "$mtu"
        return $?
    fi
    if command -v nmcli >/dev/null; then
        uuid=$(nmcli -g GENERAL.CON-UUID device show "$iface" 2>/dev/null || true)
        if [[ "$uuid" =~ ^[a-fA-F0-9-]{36}$ ]]; then
            local kind property previous
            kind=$(nmcli -g connection.type connection show uuid "$uuid") || return 1
            case "$kind" in
                802-3-ethernet) property=802-3-ethernet.mtu ;;
                802-11-wireless) property=802-11-wireless.mtu ;;
                *) print_error "Unsupported NetworkManager type: $kind"; return 1 ;;
            esac
            previous=$(nmcli -g "$property" connection show uuid "$uuid") || return 1
            print_info "Previous MTU: $previous; restore with: nmcli con mod uuid $uuid $property $previous"
            nmcli connection modify uuid "$uuid" "$property" "$mtu"
            return $?
        fi
    fi
    for file in "${NETWORK_ROOT:-}/etc/network/interfaces" "${NETWORK_ROOT:-}/etc/network/interfaces.d/"*; do
        [[ -f "$file" ]] || continue
        if awk -v iface="$iface" '$1=="iface" && $2==iface {found=1} END {exit !found}' "$file"; then
            apply_ifupdown_mtu "$file" "$iface" "$mtu"; return $?
        fi
    done
    for file in "${NETWORK_ROOT:-}/etc/sysconfig/network-scripts/ifcfg-$iface" "${NETWORK_ROOT:-}/etc/sysconfig/network/ifcfg-$iface"; do
        [[ -f "$file" && ! -L "$file" ]] || continue
        temporary=$(mktemp "${file}.XXXXXXXX") || return 1
        cp -p "$file" "$temporary" || return 1
        { sed '/^[[:space:]]*MTU=/d' "$file"; printf 'MTU=%s\n' "$mtu"; } > "$temporary" || return 1
        backup_network_file "$file" || return 1
        mv "$temporary" "$file"; return $?
    done
    if command -v networkctl >/dev/null; then
        network_file=$(LC_ALL=C networkctl status "$iface" --no-pager 2>/dev/null | sed -n 's/^[[:space:]]*Network File: //p' || true)
        if [[ "$network_file" == /*.network && -f "$network_file" ]]; then
            file="${NETWORK_ROOT:-}/etc/systemd/network/$(basename "$network_file").d/90-vm-setup-mtu.conf"
            mkdir -p "$(dirname "$file")" || return 1
            [[ ! -L "$file" ]] || return 1
            if [[ -f "$file" ]]; then backup_network_file "$file" || return 1; fi
            temporary=$(mktemp "${file}.XXXXXXXX") || return 1
            printf '[Link]\nMTUBytes=%s\n' "$mtu" > "$temporary" || return 1
            chmod 644 "$temporary"
            mv "$temporary" "$file"; return $?
        fi
    fi
    print_error "No supported active network configuration found for $iface; no addressing configuration changed."
    return 1
}

reset_mtu_config() {
    apply_mtu_persistent "$1" 1500 || return 1
    apply_mtu_immediate "$1" 1500
}

# A real JSON parser is mandatory. Invalid/non-object JSON is left untouched.
update_docker_json() {
    local daemon_json="$1" mtu="$2" temporary source_file
    command -v jq >/dev/null || { print_error 'Install jq before modifying Docker daemon.json.'; return 1; }
    [[ ! -L "$daemon_json" ]] || return 1
    [[ "$mtu" == reset ]] || validate_mtu "$mtu" || return 1
    temporary=$(mktemp "${daemon_json}.XXXXXXXX") || return 1
    source_file="$daemon_json"
    if [[ -f "$daemon_json" ]]; then
        cp -p "$daemon_json" "$temporary" || return 1
        jq -e 'type == "object"' "$daemon_json" >/dev/null || { rm -f "$temporary"; return 1; }
    else
        source_file=/dev/null
        chmod 644 "$temporary"
    fi
    local filter='.mtu = $mtu' args=()
    [[ -f "$daemon_json" ]] || args+=(-n)
    [[ "$mtu" != reset ]] || { filter='del(.mtu)'; mtu=0; }
    if ! jq "${args[@]}" --argjson mtu "$mtu" "$filter" "$source_file" > "$temporary"; then
        rm -f "$temporary"; return 1
    fi
    if [[ -f "$daemon_json" ]]; then backup_network_file "$daemon_json" || return 1; fi
    mv -- "$temporary" "$daemon_json"
}

restart_docker() {
    if [[ "$OS" == alpine ]]; then rc-service docker restart; else systemctl restart docker; fi
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

    update_docker_json "$daemon_json" "$mtu"
    print_success "Updated $daemon_json with MTU $mtu"

    apply_docker_bridges_mtu "$mtu"

    if prompt_yes_no "Restart Docker service to apply changes?" "y"; then
        if restart_docker; then
            print_success "Docker service restarted."
        else
            print_warn "Failed to restart Docker. Please restart manually."
        fi
    else
        print_info "Remember to restart Docker for changes to take effect."
    fi
}

# apply_docker_bridges_mtu applies the given MTU value to user-created Docker bridge interfaces.
# Skips docker0, docker1, etc. (managed by Docker daemon) and only applies MTU to user-created bridges (br-*).
# Checks current MTU first to avoid unnecessary changes and prints appropriate status messages.
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
        if [[ "$bridge" =~ ^docker[0-9]*$ ]]; then
            print_info "Skipping $bridge (will be reconfigured on Docker restart)"
            continue
        fi

        local current_mtu
        current_mtu=$(ip link show "$bridge" 2>/dev/null | awk 'match($0, /mtu [0-9]+/) { print substr($0, RSTART + 4, RLENGTH - 4); exit }')
        current_mtu="${current_mtu:-0}"

        if [[ "$current_mtu" == "$mtu" ]]; then
            print_info "$bridge already has MTU $mtu"
            continue
        fi

        if ip link set dev "$bridge" mtu "$mtu" 2>/dev/null; then
            print_success "Applied MTU $mtu to $bridge"
        else
            print_warn "Failed to apply MTU to $bridge"
        fi
    done
}

reset_docker_mtu() {
    local daemon_json="${DOCKER_CONFIG_FILE:-/etc/docker/daemon.json}"
    [[ -f "$daemon_json" ]] || return 0
    update_docker_json "$daemon_json" reset
}

# test_mtu_size checks if the specified MTU can reach 1.1.1.1 by pinging with ICMP packets sized to MTU-28.
# Returns 0 if the ping succeeds, 1 otherwise.
test_mtu_size() {
    local mtu="$1"
    local target="1.1.1.1"
    local packet_size=$((mtu - 28))

    if ping -4 -c 2 -W 2 -w 6 -M 'do' -s "$packet_size" "$target" &>/dev/null; then
        return 0
    fi
    return 1
}

# Largest successful candidate wins. UI stays on stderr; stdout is numeric only.
test_mtu_values() {
    local size
    for size in 1500 1450 1400 1350 1300 1250 1200 1150 1100; do
        printf 'Testing MTU %s...\n' "$size" >&2
        if test_mtu_size "$size"; then
            if prompt_yes_no "Apply MTU $size?" y >&2; then
                printf '%s\n' "$size"
                return 0
            fi
            return 1
        fi
    done
    print_warn "No probe succeeded. Check ICMP access and use iputils ping (including -M support)." >&2
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
            local test_result
            if test_result=$(test_mtu_values); then
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
    { ip -o link show | grep -vE '^[0-9]+: lo:' || true; } | while IFS= read -r line; do
        local iface mtu
        iface=$(echo "$line" | awk -F': ' '{print $2}' | cut -d'@' -f1)
        mtu=$(echo "$line" | awk 'match($0, /mtu [0-9]+/) { print substr($0, RSTART + 4, RLENGTH - 4); exit }')
        printf "  %-20s MTU: %s\n" "$iface" "$mtu"
    done
    echo ""
}

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then return 0; fi

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
    apply_mtu_persistent "$PRIMARY_IFACE" "$selected_mtu"
    apply_mtu_immediate "$PRIMARY_IFACE" "$selected_mtu"

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
