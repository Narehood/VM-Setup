#!/bin/bash
set -euo pipefail

# DIRECTORY ANCHOR
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
cd "$SCRIPT_DIR" || { echo "Failed to change directory to $SCRIPT_DIR"; exit 1; }

# VISUAL STYLING
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m'

UI_WIDTH=86

# Handle Ctrl+C gracefully
trap 'echo -e "\n${GREEN}Goodbye!${NC}"; exit 0' INT

# print_centered centers the given text within UI_WIDTH and prints it, using the optional ANSI color escape sequence provided as the second argument.
print_centered() {
    local text="$1"
    local color="${2:-$NC}"
    local padding=$(( (UI_WIDTH - ${#text}) / 2 ))
    if [ "$padding" -lt 0 ]; then padding=0; fi
    printf "${color}%${padding}s%s${NC}\n" "" "$text"
}

# print_line draws a horizontal line of length UI_WIDTH using the specified character (default '=') and color (default BLUE).
print_line() {
    local char="${1:-=}"
    local color="${2:-$BLUE}"
    printf "${color}%${UI_WIDTH}s${NC}\n" "" | sed "s/ /${char}/g"
}

# print_status prints an informational message prefixed with a cyan "[INFO]" tag.
print_status() { echo -e "${CYAN}[INFO]${NC} $1"; }
# print_success prints a success message prefixed with [OK] in green and echoes the provided message.
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
# print_warn prints a warning message prefixed with [WARN] in yellow to standard output.
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
# print_error prints MESSAGE prefixed with a red "[ERROR]" tag.
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# pause prompts the user to press Enter to return to the menu.
pause() {
    echo ""
    read -rp "Press [Enter] to return to the menu..."
}

# truncate_string shortens a string to a maximum length, appending ".." when truncation occurs.
truncate_string() {
    local str="$1"
    local max_len="$2"
    if [ ${#str} -gt "$max_len" ]; then
        echo "${str:0:$((max_len - 2))}.."
    else
        echo "$str"
    fi
}

# show_header clears the terminal and prints the ASCII art banner with the centered "QUICK APP INSTALLER  |  LIBRARY" title and a colored horizontal separator.
show_header() {
    clear
    echo -e "${BLUE}███████╗██╗   ██╗███████╗████████╗███████╗███╗   ███╗    ███████╗███████╗████████╗██╗   ██╗██████╗ ${NC}"
    echo -e "${BLUE}██╔════╝╚██╗ ██╔╝██╔════╝╚══██╔══╝██╔════╝████╗ ████║    ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗${NC}"
    echo -e "${BLUE}███████╗ ╚████╔╝ ███████╗   ██║   █████╗  ██╔████╔██║    ███████╗█████╗     ██║   ██║   ██║██████╔╝${NC}"
    echo -e "${BLUE}╚════██║  ╚██╔╝  ╚════██║   ██║   ██╔══╝  ██║╚██╔╝██║    ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝ ${NC}"
    echo -e "${BLUE}███████║   ██║   ███████║   ██║   ███████╗██║ ╚═╝ ██║    ███████║███████╗   ██║   ╚██████╔╝██║     ${NC}"
    echo -e "${BLUE}╚══════╝   ╚═╝   ╚══════╝   ╚═╝   ╚══════╝╚═╝     ╚═╝    ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝     ${NC}"
    print_centered "QUICK APP INSTALLER  |  LIBRARY" "$CYAN"
    print_line "=" "$BLUE"
}

# show_stats displays a formatted system information grid including OS, kernel, hostname, load average, memory and disk usage, and network details (IP address, subnet, gateway).
show_stats() {
    # OS Detection
    local distro="Unknown"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [ "$ID" = "alpine" ]; then
            distro="Alpine ${VERSION_ID:-}"
        else
            distro="${PRETTY_NAME:-$ID}"
        fi
    fi
    distro=$(truncate_string "$distro" 32)

    # Kernel
    local kernel
    kernel=$(truncate_string "$(uname -r)" 32)

    # Load average (more reliable than CPU snapshot)
    local cpu_load="N/A"
    if [ -f /proc/loadavg ]; then
        cpu_load=$(awk '{printf "%.2f (1m)", $1}' /proc/loadavg)
    fi

    # Memory from /proc/meminfo (more accurate)
    local mem_usage="N/A"
    if [ -f /proc/meminfo ]; then
        local mem_total mem_avail mem_used mem_pct
        mem_total=$(awk '/^MemTotal:/ {print int($2/1024)}' /proc/meminfo)
        mem_avail=$(awk '/^MemAvailable:/ {print int($2/1024)}' /proc/meminfo)
        if [ -n "$mem_total" ] && [ -n "$mem_avail" ] && [ "$mem_total" -gt 0 ]; then
            mem_used=$((mem_total - mem_avail))
            mem_pct=$((mem_used * 100 / mem_total))
            mem_usage="${mem_used}/${mem_total}MB (${mem_pct}%)"
        fi
    fi

    # Disk usage
    local disk_usage="N/A"
    if command -v df >/dev/null 2>&1; then
        disk_usage=$(df -h / 2>/dev/null | awk 'NR==2{printf "%s/%s (%s)", $3,$2,$5}')
    fi

    # Network
    local hostname_str ip_addr="N/A" subnet="N/A" gateway="N/A"
    hostname_str=$(truncate_string "$(hostname)" 30)

    if command -v ip >/dev/null 2>&1; then
        local full_ip
        full_ip=$(ip -4 addr show scope global 2>/dev/null | awk '/inet / {print $2; exit}')
        if [ -n "$full_ip" ]; then
            ip_addr="${full_ip%%/*}"
            subnet="/${full_ip##*/}"
        fi
        gateway=$(ip route 2>/dev/null | awk '/default/ {print $3; exit}')
        gateway=$(truncate_string "${gateway:-N/A}" 20)
    fi

    # DISPLAY GRID
    echo -e "${WHITE}SYSTEM INFORMATION${NC}"
    printf "  ${YELLOW}%-11s${NC} : %-30s ${YELLOW}%-11s${NC} : %s\n" "OS" "$distro" "IP Address" "$ip_addr"
    printf "  ${YELLOW}%-11s${NC} : %-30s ${YELLOW}%-11s${NC} : %s\n" "Kernel" "$kernel" "Subnet" "$subnet"
    printf "  ${YELLOW}%-11s${NC} : %-30s ${YELLOW}%-11s${NC} : %s\n" "Hostname" "$hostname_str" "Gateway" "$gateway"
    print_line "-" "$BLUE"
    printf "  ${YELLOW}%-11s${NC} : %-30s ${YELLOW}%-11s${NC} : %s\n" "Load Avg" "$cpu_load" "Memory" "$mem_usage"
    printf "  ${YELLOW}%-11s${NC} : %-30s\n" "Disk Usage" "$disk_usage"
    print_line "=" "$BLUE"
}

# Define installers as an associative array for easy management
declare -A INSTALLERS=(
    [1]="WordPress.sh:WordPress"
    [2]="XenOrchestra.sh:Xen Orchestra"
    [3]="UniFi-Controller.sh:UniFi Controller"
    [4]="CloudFlare-Tunnels.sh:CloudFlare Tunnels"
    [5]="Pangolin.sh:Pangolin Tunnel"
    [6]="Newt.sh:Newt VPN Node"
)

# execute_installer validates a script's existence/readability, offers to fix its executable bit, runs the script, reports a non-zero exit code, and prompts the user to return to the menu or exit.
execute_installer() {
    local script_name="$1"
    local display_name="$2"

    if [ ! -f "$script_name" ]; then
        print_error "Script '$script_name' not found."
        pause
        return 1
    fi

    if [ ! -r "$script_name" ]; then
        print_error "Script '$script_name' not readable."
        pause
        return 1
    fi

    # Check if executable, offer to fix
    if [ ! -x "$script_name" ]; then
        print_warn "Script is not executable."
        read -rp "  Make it executable? (Y/n): " response
        response="${response:-y}"
        if [[ "$response" =~ ^[Yy]$ ]]; then
            chmod +x "$script_name" && print_success "Made executable." || {
                print_error "Failed to set executable."
                pause
                return 1
            }
        fi
    fi

    echo -e "\n${GREEN}>>> Launching: $display_name${NC}"
    print_line "-" "$BLUE"
    sleep 0.5

    bash "$script_name"
    local exit_code=$?

    echo ""
    print_line "-" "$BLUE"

    if [ $exit_code -ne 0 ]; then
        print_warn "Script exited with code: $exit_code"
    fi

    read -rp "Press [Enter] to return to menu or type 'exit': " next_action
    if [ "$next_action" = "exit" ]; then
        echo -e "\n${GREEN}Goodbye!${NC}"
        exit 0
    fi
}

# show_menu displays the available installers in a two-column, numbered menu and adds a "0. Return to Main Menu" option.
show_menu() {
    echo -e "${WHITE}AVAILABLE INSTALLERS${NC}"

    # Display in two columns
    local left_keys=(1 2 3)
    local right_keys=(4 5 6)

    for i in "${!left_keys[@]}"; do
        local lk="${left_keys[$i]}"
        local rk="${right_keys[$i]}"
        local left_name="${INSTALLERS[$lk]#*:}"
        local right_name="${INSTALLERS[$rk]#*:}"
        printf "  ${CYAN}%d.${NC} %-43s ${CYAN}%d.${NC} %s\n" "$lk" "$left_name" "$rk" "$right_name"
    done

    printf "  ${CYAN}0.${NC} ${RED}%s${NC}\n" "Return to Main Menu"
    echo ""
    print_line "-" "$BLUE"
}

# MAIN LOOP
while true; do
    show_header
    show_stats
    show_menu

    read -rp "  Enter selection [0-6]: " choice

    case "$choice" in
        [1-6])
            if [ -n "${INSTALLERS[$choice]:-}" ]; then
                script="${INSTALLERS[$choice]%%:*}"
                name="${INSTALLERS[$choice]#*:}"
                execute_installer "$script" "$name"
            else
                print_error "Invalid option."
                sleep 1
            fi
            ;;
        0|q|exit)
            echo -e "\n${GREEN}Returning to Main Menu...${NC}"
            exit 0
            ;;
        "")
            ;;
        *)
            print_error "Invalid option: $choice"
            sleep 1
            ;;
    esac
done