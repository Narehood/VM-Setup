#!/bin/bash

# --- 1. CRITICAL SETUP & RESTART FIX ---
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
cd "$SCRIPT_DIR" || { echo "Failed to change directory to $SCRIPT_DIR"; exit 1; }

# --- 2. VISUAL STYLING ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m'

UI_WIDTH=66
VERSION="3.2.0"

# Handle Ctrl+C gracefully
trap 'echo -e "\n${GREEN}Goodbye!${NC}"; exit 0' SIGINT SIGTERM

print_centered() {
    local text="$1"
    local color="${2:-$NC}"
    local padding=$(( (UI_WIDTH - ${#text}) / 2 ))
    printf "${color}%${padding}s%s${NC}\n" "" "$text"
}

print_line() {
    local char="${1:-=}"
    local color="${2:-$BLUE}"
    printf "${color}%${UI_WIDTH}s${NC}\n" | tr ' ' "$char"
}

print_status() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

pause() {
    echo ""
    read -rp "Press [Enter] to return to the menu..."
}

confirm_prompt() {
    local prompt="$1"
    local default="${2:-n}"
    local response
    
    read -rp "$prompt" response
    response="${response:-$default}"
    [[ "$response" =~ ^[Yy]$ ]]
}

show_header() {
    clear
    echo -e "${BLUE}██╗   ██╗███╗   ███╗    ███████╗███████╗████████╗██╗   ██╗██████╗ ${NC}"
    echo -e "${BLUE}██║   ██║████╗ ████║    ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗${NC}"
    echo -e "${BLUE}██║   ██║██╔████╔██║    ███████╗█████╗     ██║   ██║   ██║██████╔╝${NC}"
    echo -e "${BLUE}╚██╗ ██╔╝██║╚██╔╝██║    ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝ ${NC}"
    echo -e "${BLUE} ╚████╔╝ ██║ ╚═╝ ██║    ███████║███████╗   ██║   ╚██████╔╝██║     ${NC}"
    echo -e "${BLUE}  ╚═══╝  ╚═╝     ╚═╝    ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝     ${NC}"
    print_centered "VERSION $VERSION  |  BY: MICHAEL NAREHOOD" "$CYAN"
    print_line "=" "$BLUE"
}

truncate_string() {
    local str="$1"
    local max_len="$2"
    if [ ${#str} -gt "$max_len" ]; then
        echo "${str:0:$((max_len - 2))}.."
    else
        echo "$str"
    fi
}

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
    distro=$(truncate_string "$distro" 22)

    # Kernel
    local kernel
    kernel=$(truncate_string "$(uname -r)" 22)

    # Uptime
    local uptime_str="Unknown"
    if [ -f /proc/uptime ]; then
        local uptime_secs
        uptime_secs=$(cut -d. -f1 /proc/uptime)
        local days=$((uptime_secs / 86400))
        local hours=$(( (uptime_secs % 86400) / 3600 ))
        local mins=$(( (uptime_secs % 3600) / 60 ))
        if [ $days -gt 0 ]; then
            uptime_str="${days}d ${hours}h ${mins}m"
        elif [ $hours -gt 0 ]; then
            uptime_str="${hours}h ${mins}m"
        else
            uptime_str="${mins}m"
        fi
    fi

    # Load average (more accurate than instantaneous CPU calc)
    local cpu_load="Unknown"
    if [ -f /proc/loadavg ]; then
        cpu_load=$(awk '{printf "%.2f (1m avg)", $1}' /proc/loadavg)
    fi

    # Memory
    local mem_usage="Unknown"
    if command -v free >/dev/null 2>&1; then
        mem_usage=$(free -m | awk 'NR==2{printf "%s/%sMB (%.0f%%)", $3,$2,$3*100/$2}')
    fi

    # Disk
    local disk_usage="Unknown"
    if command -v df >/dev/null 2>&1; then
        disk_usage=$(df -h / 2>/dev/null | awk 'NR==2{printf "%s/%s (%s)", $3,$2,$5}')
    fi

    # Network
    local hostname_str
    hostname_str=$(truncate_string "$(hostname)" 20)

    local ip_addr="Unknown"
    local subnet="Unknown"
    local gateway="Unknown"

    if command -v ip >/dev/null 2>&1; then
        local full_ip
        full_ip=$(ip -4 addr show scope global 2>/dev/null | awk '/inet / {print $2; exit}')
        if [ -n "$full_ip" ]; then
            ip_addr="${full_ip%%/*}"
            subnet="/${full_ip##*/}"
        fi
        gateway=$(ip route 2>/dev/null | awk '/default/ {print $3; exit}')
        gateway=$(truncate_string "${gateway:-N/A}" 15)
    fi

    # Display
    echo -e "${WHITE}SYSTEM INFORMATION${NC}"
    printf "  ${YELLOW}%-11s${NC} : %-20s ${YELLOW}%-11s${NC} : %s\n" "OS" "$distro" "IP Address" "${ip_addr:-N/A}"
    printf "  ${YELLOW}%-11s${NC} : %-20s ${YELLOW}%-11s${NC} : %s\n" "Kernel" "$kernel" "Subnet" "${subnet:-N/A}"
    printf "  ${YELLOW}%-11s${NC} : %-20s ${YELLOW}%-11s${NC} : %s\n" "Hostname" "$hostname_str" "Gateway" "${gateway:-N/A}"
    print_line "-" "$BLUE"
    printf "  ${YELLOW}%-11s${NC} : %-20s ${YELLOW}%-11s${NC} : %s\n" "Load Avg" "$cpu_load" "Memory" "$mem_usage"
    printf "  ${YELLOW}%-11s${NC} : %-20s ${YELLOW}%-11s${NC} : %s\n" "Disk Usage" "$disk_usage" "Uptime" "$uptime_str"
    print_line "=" "$BLUE"
}

check_for_updates() {
    echo ""
    print_status "Checking for updates..."

    if ! command -v git >/dev/null 2>&1; then
        print_error "Git is not installed. Cannot check for updates."
        sleep 2
        return 1
    fi

    if [ ! -d "$SCRIPT_DIR/.git" ]; then
        print_warn "Not a git repository. Skipping update check."
        sleep 2
        return 1
    fi

    if ! git fetch --quiet 2>/dev/null; then
        print_error "Failed to fetch from remote. Check your network connection."
        sleep 2
        return 1
    fi

    local local_rev remote_rev
    local_rev=$(git rev-parse @ 2>/dev/null)

    if ! remote_rev=$(git rev-parse '@{u}' 2>/dev/null); then
        print_error "No upstream branch configured. Skipping update check."
        sleep 2
        return 1
    fi

    if [ "$local_rev" = "$remote_rev" ]; then
        print_success "Menu is up to date."
        sleep 1
    else
        print_warn "New version available."
        if confirm_prompt "Download and apply updates? (y/N): " "n"; then
            if git pull --quiet; then
                print_success "Updated successfully. Restarting..."
                sleep 1
                exec bash "$SCRIPT_PATH"
            else
                print_error "Update failed. Please try manually with 'git pull'."
                sleep 2
            fi
        else
            print_status "Update skipped."
            sleep 1
        fi
    fi
}

execute_script() {
    local script_name="$1"
    local full_path="$SCRIPT_DIR/Installers/$script_name"

    if [ ! -f "$full_path" ]; then
        print_error "Script not found: $full_path"
        pause
        return 1
    fi

    if [ ! -r "$full_path" ]; then
        print_error "Script not readable: $full_path"
        pause
        return 1
    fi

    echo -e "\n${GREEN}>>> Executing: $script_name${NC}"
    sleep 0.5

    bash "$full_path"
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        print_warn "Script exited with code: $exit_code"
    fi

    pause
}

show_help() {
    clear
    print_line "=" "$BLUE"
    print_centered "HELP & INFORMATION" "$WHITE"
    print_line "=" "$BLUE"
    echo ""
    echo -e "  ${WHITE}VM Setup Menu${NC} - Version $VERSION"
    echo -e "  A comprehensive tool for initial VM configuration."
    echo ""
    echo -e "  ${YELLOW}Menu Options:${NC}"
    echo -e "    ${CYAN}1${NC} - Run initial server configuration (hostname, tools, etc.)"
    echo -e "    ${CYAN}2${NC} - Browse and install common applications"
    echo -e "    ${CYAN}3${NC} - Prepare system for Docker installation"
    echo -e "    ${CYAN}4${NC} - Configure automatic security patch updates"
    echo -e "    ${CYAN}5${NC} - Run full system update"
    echo -e "    ${CYAN}6${NC} - Check for and apply menu updates"
    echo -e "    ${CYAN}7${NC} - Launch LinUtil utility"
    echo -e "    ${CYAN}8${NC} - Display this help screen"
    echo -e "    ${CYAN}0${NC} - Exit the menu"
    echo ""
    echo -e "  ${YELLOW}Location:${NC} $SCRIPT_DIR"
    echo ""
    print_line "=" "$BLUE"
    pause
}

# --- INITIAL UPDATE CHECK ---
clear
check_for_updates

# --- MAIN LOOP ---
while true; do
    show_header
    show_stats

    echo -e "${WHITE}MENU OPTIONS${NC}"
    printf "  ${CYAN}1.${NC} %-33s ${CYAN}5.${NC} %s\n" "Server Initial Config" "Run System Updates"
    printf "  ${CYAN}2.${NC} %-33s ${CYAN}6.${NC} %s\n" "Application Installers" "Update This Menu"
    printf "  ${CYAN}3.${NC} %-33s ${CYAN}7.${NC} %s\n" "Docker Host Preparation" "Launch LinUtil"
    printf "  ${CYAN}4.${NC} %-33s ${CYAN}8.${NC} %s\n" "Auto Security Patches" "Help / About"
    echo ""
    printf "  ${CYAN}0.${NC} ${RED}%s${NC}\n" "Exit"
    echo ""
    print_line "-" "$BLUE"
    read -rp "  Enter selection [0-8]: " choice

    case "$choice" in
        1) execute_script "serverSetup.sh" ;;
        2) execute_script "installer.sh" ;;
        3) execute_script "Docker-Prep.sh" ;;
        4) execute_script "Automated-Security-Patches.sh" ;;
        5) execute_script "systemUpdate.sh" ;;
        6) check_for_updates ;;
        7) execute_script "linutil.sh" ;;
        8|h|help) show_help ;;
        0|q|exit) echo -e "\n${GREEN}Goodbye!${NC}"; exit 0 ;;
        "") ;; # Ignore empty input, just refresh
        *) print_error "Invalid option: $choice"; sleep 1 ;;
    esac
done
