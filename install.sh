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
NC='\033[0m' # No Color

# Standard Width for the UI
UI_WIDTH=66

# Function to print a centered line
print_centered() {
    local text="$1"
    local color="${2:-$NC}"
    local width=$UI_WIDTH
    local padding=$(( (width - ${#text}) / 2 ))
    printf "${color}%${padding}s%s${NC}\n" "" "$text"
}

# Function to print a separator line
print_line() {
    local char="${1:-=}"
    local color="${2:-$BLUE}"
    local line=""
    for ((i=0; i<UI_WIDTH; i++)); do line="${line}${char}"; done
    echo -e "${color}${line}${NC}"
}

pause() {
    echo ""
    read -p "Press [Enter] to return to the menu..."
}

show_header() {
    clear
    echo -e "${BLUE}██╗   ██╗███╗   ███╗    ███████╗███████╗████████╗██╗   ██╗██████╗ ${NC}"
    echo -e "${BLUE}██║   ██║████╗ ████║    ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗${NC}"
    echo -e "${BLUE}██║   ██║██╔████╔██║    ███████╗█████╗     ██║   ██║   ██║██████╔╝${NC}"
    echo -e "${BLUE}╚██╗ ██╔╝██║╚██╔╝██║    ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝ ${NC}"
    echo -e "${BLUE} ╚████╔╝ ██║ ╚═╝ ██║    ███████║███████╗   ██║   ╚██████╔╝██║     ${NC}"
    echo -e "${BLUE}  ╚═══╝  ╚═╝     ╚═╝    ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝     ${NC}"
    print_centered "VERSION 3.0.0  |  ADMIN CONSOLE" "$CYAN"
    print_line "=" "$BLUE"
}

show_stats() {
    # --- DATA COLLECTION ---
    
    # OS Detection & Truncation
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [ "$ID" = "alpine" ]; then DISTRO="Alpine $VERSION_ID"; else DISTRO="${PRETTY_NAME:-$ID}"; fi
    else
        DISTRO="Unknown"
    fi
    if [ ${#DISTRO} -gt 22 ]; then DISTRO="${DISTRO:0:20}.."; fi

    # Kernel
    KERNEL=$(uname -r)
    if [ ${#KERNEL} -gt 15 ]; then KERNEL="${KERNEL:0:13}.."; fi

    # Resources
    CPU_LOAD=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {printf "%.1f%%", usage}')
    MEM_USAGE=$(free -m | awk 'NR==2{printf "%s/%sMB (%.0f%%)", $3,$2,$3*100/$2 }')
    DISK_USAGE=$(df -h / | awk '$NF=="/"{printf "%s/%s (%s)", $3,$2,$5}')
    
    # Network
    HOSTNAME=$(hostname)
    if [ ${#HOSTNAME} -gt 20 ]; then HOSTNAME="${HOSTNAME:0:18}.."; fi

    if command -v ip &> /dev/null; then
        IP_ADDR=$(ip -4 addr show scope global | grep inet | awk '{print $2}' | cut -d/ -f1 | head -n 1)
    else
        IP_ADDR="Unknown"
    fi
    
    GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n 1)
    if [ ${#GATEWAY} -gt 15 ]; then GATEWAY="${GATEWAY:0:13}.."; fi

    # --- DISPLAY GRID ---
    echo -e "${WHITE}SYSTEM
