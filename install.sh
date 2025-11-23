#!/bin/bash

# --- 1. CRITICAL SETUP & RESTART FIX ---
# Resolve the absolute path of this script immediately.
# This fixes the "install.sh not found" error after git pull.
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
SCRIPT_NAME="$(basename "$SCRIPT_PATH")"

cd "$SCRIPT_DIR" || { echo "Failed to change directory to $SCRIPT_DIR"; exit 1; }

# --- 2. VISUAL STYLING ---
# Define color palette
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Function to pause and wait for user input
pause() {
    echo ""
    read -p "Press [Enter] to return to the menu..."
}

# Function to display the dashboard header
show_header() {
    clear
    # Simple ASCII Header
    echo -e "${BLUE}██╗   ██╗███╗   ███╗    ███████╗███████╗████████╗██╗   ██╗██████╗ ${NC}"
    echo -e "${BLUE}██║   ██║████╗ ████║    ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗${NC}"
    echo -e "${BLUE}██║   ██║██╔████╔██║    ███████╗█████╗     ██║   ██║   ██║██████╔╝${NC}"
    echo -e "${BLUE}╚██╗ ██╔╝██║╚██╔╝██║    ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝ ${NC}"
    echo -e "${BLUE} ╚████╔╝ ██║ ╚═╝ ██║    ███████║███████╗   ██║   ╚██████╔╝██║     ${NC}"
    echo -e "${BLUE}  ╚═══╝  ╚═╝     ╚═╝    ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝     ${NC}"
    echo -e "${CYAN}                  VERSION 3.0.1  |  ADMIN CONSOLE                  ${NC}"
    echo -e "${BLUE}===================================================================${NC}"
}

# Function to gather and display system stats
show_stats() {
    # OS Detection
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [ "$ID" = "alpine" ]; then
            DISTRO="Alpine $VERSION_ID"
        else
            DISTRO="${PRETTY_NAME:-$ID}"
        fi
    else
        DISTRO="Unknown Linux"
    fi

    # Resources
    KERNEL=$(uname -r)
    # Use a safer CPU check that doesn't rely on delay
    CPU_LOAD=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {printf "%.1f%%", usage}')
    MEM_USAGE=$(free -m | awk 'NR==2{printf "%s/%sMB (%.1f%%)", $3,$2,$3*100/$2 }')
    DISK_USAGE=$(df -h / | awk '$NF=="/"{printf "%s/%s (%s)", $3,$2,$5}')
    
    # Network
    HOSTNAME=$(hostname)
    if command -v ip &> /dev/null; then
        IP_ADDR=$(ip -4 addr show scope global | grep inet | awk '{print $2}' | cut -d/ -f1 | head -n 1)
    else
        IP_ADDR="Unknown"
    fi

    # Display Grid
    echo -e "${WHITE}SYSTEM INFORMATION${NC}"
    printf "  ${YELLOW}%-15s${NC} : %-30s ${YELLOW}%-15s${NC} : %s\n" "OS" "$DISTRO" "Hostname" "$HOSTNAME"
    printf "  ${YELLOW}%-15s${NC} : %-30s ${YELLOW}%-15s${NC} : %s\n" "Kernel" "$KERNEL" "IP Address" "${IP_ADDR:-N/A}"
    echo -e "${BLUE}-------------------------------------------------------------------${NC}"
    printf "  ${YELLOW}%-15s${NC} : %-30s ${YELLOW}%-15s${NC} : %s\n" "CPU Usage" "$CPU_LOAD" "Memory" "$MEM_USAGE"
    printf "  ${YELLOW}%-15s${NC} : %-30s ${YELLOW}%-15s${NC} : %s\n" "Disk Usage" "$DISK_USAGE" "Gateway" "$(ip route | grep default | awk '{print $3}')"
    echo -e "${BLUE}===================================================================${NC}"
}

# Function to check for updates
check_for_updates() {
    echo -e "\n${CYAN}[INFO]${NC} Checking for updates..."
    git fetch
    
    LOCAL=$(git rev-parse @)
    if ! REMOTE=$(git rev-parse @{u} 2>/dev/null); then
        echo -e "${RED}[ERROR]${NC} No upstream branch configured."
        pause
        return
    fi

    if [ "$LOCAL" = "$REMOTE" ]; then
        echo -e "${GREEN}[OK]${NC} Menu is up to date."
        sleep 1
    else
        echo -e "${YELLOW}[UPDATE]${NC} New version available."
        read -p "Download and apply updates? (y/n): " pull_choice
        if [ "$pull_choice" = "y" ]; then
            git pull
            echo -e "${GREEN}[SUCCESS]${NC} Updated successfully."
            echo "Restarting menu..."
            sleep 1
            # FIX: Explicitly call bash with the resolved path
            exec bash "$SCRIPT_PATH" "$@"
        else
            echo "Update skipped."
        fi
    fi
}

# Function to execute installer scripts
execute_installerScript() {
    local script_name=$1
    local full_path="$SCRIPT_DIR/Installers/$script_name"

    if [ -f "$full_path" ]; then
        echo -e "\n${GREEN}>>> Executing: $script_name ${NC}"
        # Give a moment to read the message
        sleep 0.5
        bash "$full_path"
    else
        echo -e "\n${RED}[ERROR]${NC} Script not found at:"
        echo "       $full_path"
    fi
    pause
}

# --- MAIN LOOP ---
while true; do
    show_header
    show_stats
    
    echo -e "${WHITE}MENU OPTIONS${NC}"
    echo -e "  ${CYAN}1.${NC} Server Initial Config        ${CYAN}5.${NC} Run System Updates"
    echo -e "  ${CYAN}2.${NC} Application Installers       ${CYAN}6.${NC} Update This Menu"
    echo -e "  ${CYAN}3.${NC} Docker Host Preparation      ${CYAN}7.${NC} Launch LinUtil"
    echo -e "  ${CYAN}4.${NC} Auto Security Patches        ${CYAN}9.${NC} ${RED}Exit${NC}"
    echo ""
    echo -e "${BLUE}-------------------------------------------------------------------${NC}"
    read -p "  Enter selection [1-9]: " choice

    case $choice in
        1) execute_installerScript "serverSetup.sh" ;;
        2) execute_installerScript "installer.sh" ;;
        3) execute_installerScript "Docker-Prep.sh" ;;
        4) execute_installerScript "Automated-Security-Patches.sh" ;;
        5) execute_installerScript "systemUpdate.sh" ;;
        6) check_for_updates ;;
        7) execute_installerScript "linutil.sh" ;;
        9) 
            echo -e "\n${GREEN}Goodbye!${NC}"
            exit 0 
            ;;
        *) 
            echo -e "\n${RED}Invalid option selected.${NC}"
            sleep 1
            ;;
    esac
done
