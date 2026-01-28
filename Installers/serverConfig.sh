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

# get_current_branch prints the current Git branch name or "unknown" if unavailable.
get_current_branch() {
    git branch --show-current 2>/dev/null || echo "unknown"
}

# show_header clears the terminal and prints the ASCII art banner with the centered title and a colored horizontal separator.
show_header() {
    clear
    echo -e "${BLUE}███████╗██╗   ██╗███████╗████████╗███████╗███╗   ███╗    ███████╗███████╗████████╗██╗   ██╗██████╗ ${NC}"
    echo -e "${BLUE}██╔════╝╚██╗ ██╔╝██╔════╝╚══██╔══╝██╔════╝████╗ ████║    ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗${NC}"
    echo -e "${BLUE}███████╗ ╚████╔╝ ███████╗   ██║   █████╗  ██╔████╔██║    ███████╗█████╗     ██║   ██║   ██║██████╔╝${NC}"
    echo -e "${BLUE}╚════██║  ╚██╔╝  ╚════██║   ██║   ██╔══╝  ██║╚██╔╝██║    ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝ ${NC}"
    echo -e "${BLUE}███████║   ██║   ███████║   ██║   ███████╗██║ ╚═╝ ██║    ███████║███████╗   ██║   ╚██████╔╝██║     ${NC}"
    echo -e "${BLUE}╚══════╝   ╚═╝   ╚══════╝   ╚═╝   ╚══════╝╚═╝     ╚═╝    ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝     ${NC}"
    print_centered "SERVER CONFIGURATION" "$CYAN"
    print_line "=" "$BLUE"
}

# show_stats displays a formatted system information grid including OS, kernel, hostname, load average, memory and disk usage, network details, uptime, and current Git branch.
show_stats() {
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

    local kernel
    kernel=$(truncate_string "$(uname -r)" 32)

    local uptime_str="N/A"
    if [ -f /proc/uptime ]; then
        local uptime_secs
        uptime_secs=$(cut -d. -f1 /proc/uptime)
        local days=$((uptime_secs / 86400))
        local hours=$(( (uptime_secs % 86400) / 3600 ))
        local mins=$(( (uptime_secs % 3600) / 60 ))
        if [ "$days" -gt 0 ]; then
            uptime_str="${days}d ${hours}h ${mins}m"
        elif [ "$hours" -gt 0 ]; then
            uptime_str="${hours}h ${mins}m"
        else
            uptime_str="${mins}m"
        fi
    fi

    local cpu_load="N/A"
    if [ -f /proc/loadavg ]; then
        cpu_load=$(LC_ALL=C awk '{printf "%.2f (1m)", $1}' /proc/loadavg)
    fi

    local mem_usage="N/A"
    if [ -f /proc/meminfo ]; then
        local mem_total mem_avail mem_used mem_pct
        mem_total=$(LC_ALL=C awk '/^MemTotal:/ {print int($2/1024)}' /proc/meminfo)
        mem_avail=$(LC_ALL=C awk '/^MemAvailable:/ {print int($2/1024)}' /proc/meminfo)
        if [ -n "$mem_total" ] && [ -n "$mem_avail" ] && [ "$mem_total" -gt 0 ]; then
            mem_used=$((mem_total - mem_avail))
            mem_pct=$((mem_used * 100 / mem_total))
            mem_usage="${mem_used}/${mem_total}MB (${mem_pct}%)"
        fi
    fi

    local disk_usage="N/A"
    if command -v df >/dev/null 2>&1; then
        local disk_info
        disk_info=$(LC_ALL=C df -P / 2>/dev/null | awk 'NR==2 {print $3, $2, $5}')
        if [ -n "$disk_info" ]; then
            local used total pct
            read -r used total pct <<< "$disk_info"
            if [ -n "$used" ] && [ -n "$total" ] && [ -n "$pct" ]; then
                local used_h total_h
                if [ "$total" -ge 1048576 ]; then
                    used_h="$((used / 1048576))G"
                    total_h="$((total / 1048576))G"
                else
                    used_h="$((used / 1024))M"
                    total_h="$((total / 1024))M"
                fi
                disk_usage="${used_h}/${total_h} (${pct})"
            fi
        fi
    fi

    local hostname_str ip_addr="N/A" subnet="N/A" gateway="N/A"
    hostname_str=$(truncate_string "$(hostname)" 30)

    if command -v ip >/dev/null 2>&1; then
        local full_ip
        full_ip=$(LC_ALL=C ip -4 addr show scope global 2>/dev/null | awk '/inet / {print $2; exit}')
        if [ -n "$full_ip" ]; then
            ip_addr="${full_ip%%/*}"
            subnet="/${full_ip##*/}"
        fi
        gateway=$(LC_ALL=C ip route 2>/dev/null | awk '/default/ {print $3; exit}')
        gateway=$(truncate_string "${gateway:-N/A}" 20)
    fi

    local current_branch
    current_branch=$(truncate_string "$(get_current_branch)" 30)

    echo -e "${WHITE}SYSTEM INFORMATION${NC}"
    printf "  ${YELLOW}%-11s${NC} : %-30s ${YELLOW}%-11s${NC} : %s\n" "OS" "$distro" "IP Address" "$ip_addr"
    printf "  ${YELLOW}%-11s${NC} : %-30s ${YELLOW}%-11s${NC} : %s\n" "Kernel" "$kernel" "Subnet" "$subnet"
    printf "  ${YELLOW}%-11s${NC} : %-30s ${YELLOW}%-11s${NC} : %s\n" "Hostname" "$hostname_str" "Gateway" "$gateway"
    print_line "-" "$BLUE"
    printf "  ${YELLOW}%-11s${NC} : %-30s ${YELLOW}%-11s${NC} : %s\n" "Load Avg" "$cpu_load" "Memory" "$mem_usage"
    printf "  ${YELLOW}%-11s${NC} : %-30s ${YELLOW}%-11s${NC} : %s\n" "Disk Usage" "$disk_usage" "Uptime" "$uptime_str"
    print_line "-" "$BLUE"
    printf "  ${YELLOW}%-11s${NC} : %-30s\n" "Branch" "$current_branch"
    print_line "=" "$BLUE"
}

# Config scripts: format is "script.sh:Display Name"
declare -A CONFIG_SCRIPTS=(
    [1]="mtu-fix.sh:MTU Configuration"
)

# Get total number of options for menu display
TOTAL_OPTIONS=${#CONFIG_SCRIPTS[@]}

# execute_config validates a script's existence/readability, offers to fix its executable bit, runs the script, reports a non-zero exit code, and prompts the user to return to the menu or exit.
execute_config() {
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

# show_menu displays the available config scripts in a formatted menu.
show_menu() {
    echo -e "${WHITE}CONFIGURATION OPTIONS${NC}"

    # Single column for now, can expand to two columns as more options are added
    for key in $(echo "${!CONFIG_SCRIPTS[@]}" | tr ' ' '\n' | sort -n); do
        local name="${CONFIG_SCRIPTS[$key]#*:}"
        printf "  ${CYAN}%d.${NC} %s\n" "$key" "$name"
    done

    echo ""
    printf "  ${CYAN}0.${NC} ${RED}%s${NC}\n" "Return to Main Menu"
    echo ""
    print_line "-" "$BLUE"
}

# MAIN LOOP
while true; do
    show_header
    show_stats
    show_menu

    read -rp "  Enter selection [0-$TOTAL_OPTIONS]: " choice

    case "$choice" in
        [1-9])
            if [ -n "${CONFIG_SCRIPTS[$choice]:-}" ]; then
                script="${CONFIG_SCRIPTS[$choice]%%:*}"
                name="${CONFIG_SCRIPTS[$choice]#*:}"
                execute_config "$script" "$name"
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
