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
EXIT_APP_CODE=42

trap 'echo -e "\n${GREEN}Goodbye!${NC}"; exit $EXIT_APP_CODE' INT

# print_centered centers the given text within UI_WIDTH using an optional color and prints a single padded line.
print_centered() {
    local text="$1"
    local color="${2:-$NC}"
    local padding=$(( (UI_WIDTH - ${#text}) / 2 ))
    if [ "$padding" -lt 0 ]; then padding=0; fi
    printf "${color}%${padding}s%s${NC}\n" "" "$text"
}

# print_line prints a horizontal line of length UI_WIDTH using the specified character (default '=') and color (default $BLUE).
print_line() {
    local char="${1:-=}"
    local color="${2:-$BLUE}"
    printf "${color}%${UI_WIDTH}s${NC}\n" "" | sed "s/ /${char}/g"
}

# print_status prints an informational message prefixed with a cyan "[INFO]" tag.
print_status() { echo -e "${CYAN}[INFO]${NC} $1"; }
# print_success prints the given message prefixed with a green `[OK]` tag to stdout.
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
# print_warn prints a warning message prefixed with a yellow "[WARN]" tag.
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
# print_error prints MESSAGE to stdout prefixed with a red '[ERROR]' tag.
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# pause prints a blank line and waits for the user to press Enter to return to the menu.
pause() {
    echo ""
    read -rp "Press [Enter] to return to the menu..."
}

# truncate_string truncates a string to max_len characters (including a trailing '..' when truncated) and echoes the result.
truncate_string() {
    local str="$1"
    local max_len="$2"
    if [ ${#str} -gt "$max_len" ]; then
        echo "${str:0:$((max_len - 2))}.."
    else
        echo "$str"
    fi
}

# get_current_branch prints the current Git branch name or "unknown" if the branch cannot be determined.
get_current_branch() {
    git branch --show-current 2>/dev/null || echo "unknown"
}

# show_header clears the screen and prints the stylized ASCII art header, a centered title, and a decorative line.
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

# show_stats prints a formatted system information panel to stdout.
# It displays OS, kernel, hostname, IP/subnet/gateway, load average, memory and disk usage, uptime, and the current Git branch.
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

declare -A INSTALLERS=(
    [1]="WordPress.sh:WordPress"
    [2]="XenOrchestra.sh:Xen Orchestra"
    [3]="UniFi-Controller.sh:UniFi Controller"
    [4]="CloudFlare-Tunnels.sh:CloudFlare Tunnels"
    [5]="Pangolin.sh:Pangolin Tunnel"
    [6]="Newt.sh:Newt VPN Node"
)

TOTAL_OPTIONS=${#INSTALLERS[@]}

# execute_installer validates and runs an installer script (first arg: script path, second arg: display name), reports non-zero exit codes, and prompts the user to continue, return to the main menu, or quit.
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

    set +e
    bash "$script_name"
    local exit_code=$?
    set -e

    echo ""
    print_line "-" "$BLUE"

    if [ $exit_code -ne 0 ]; then
        print_warn "Script exited with code: $exit_code"
    fi

    echo ""
    read -rp "Press [Enter] to continue, [b] for main menu, [q] to quit: " next_action
    case "$next_action" in
        b|B)
            echo -e "\n${GREEN}Returning to Main Menu...${NC}"
            exit 0
            ;;
        q|Q)
            echo -e "\n${GREEN}Goodbye!${NC}"
            exit $EXIT_APP_CODE
            ;;
    esac
}

# show_menu displays the available installers in two columns (keys 1–6) and prints options to return to the main menu (0) or exit (q).
show_menu() {
    echo -e "${WHITE}AVAILABLE INSTALLERS${NC}"

    local left_keys=(1 2 3)
    local right_keys=(4 5 6)

    for i in "${!left_keys[@]}"; do
        local lk="${left_keys[$i]}"
        local rk="${right_keys[$i]}"
        local left_name="${INSTALLERS[$lk]#*:}"
        local right_name="${INSTALLERS[$rk]#*:}"
        printf "  ${CYAN}%d.${NC} %-43s ${CYAN}%d.${NC} %s\n" "$lk" "$left_name" "$rk" "$right_name"
    done

    echo ""
    printf "  ${CYAN}0.${NC} %-38s ${CYAN}q.${NC} ${RED}%s${NC}\n" "Return to Main Menu" "Exit"
    echo ""
    print_line "-" "$BLUE"
}

while true; do
    show_header
    show_stats
    show_menu

    read -rp "  Enter selection [0-$TOTAL_OPTIONS, b, q]: " choice

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
        0|b|back)
            echo -e "\n${GREEN}Returning to Main Menu...${NC}"
            exit 0
            ;;
        q|qq|exit)
            echo -e "\n${GREEN}Goodbye!${NC}"
            exit $EXIT_APP_CODE
            ;;
        "")
            ;;
        *)
            print_error "Invalid option: $choice"
            sleep 1
            ;;
    esac
done
