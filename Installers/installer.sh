#!/bin/bash

# 1. DIRECTORY ANCHOR
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || { echo "Failed to change directory to $SCRIPT_DIR"; exit 1; }

# Function to display the menu
show_menu() {
    clear
    echo -e "\033[0;32m=====================================\033[0m"
    echo -e "          \033[1;34mLinux Quick Installer Menu\033[0m"
    echo -e "\033[0;32m=====================================\033[0m"
    echo -e "\033[1;32mResource Information\033[0m"
    echo -e "-------------------------------------"

    # Distro Check
    DISTRO=""
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [ "$ID" = "alpine" ]; then
            DISTRO="Alpine Linux $VERSION_ID"
        elif command -v lsb_release &> /dev/null; then
            DISTRO="$(lsb_release -d | cut -f2)"
        else
            DISTRO="$PRETTY_NAME"
        fi
    else
        DISTRO="Unknown Linux Distribution"
    fi
    echo -e "Linux Distribution: \033[1;33m$DISTRO\033[0m"
    echo -e "Kernel Version: \033[1;33m$(uname -r)\033[0m"
    
    # Efficient CPU Check
    CPU_USAGE=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {printf "%.2f%%", usage}')
    echo -e "CPU Usage: \033[1;33m$CPU_USAGE\033[0m"
    
    echo -e "Memory Usage: \033[1;33m$(free -m | awk 'NR==2{printf "Memory Usage: %s/%sMB (%.2f%%)\n", $3,$2,$3*100/$2 }')\033[0m"
    echo -e "Disk Usage: \033[1;33m$(df -h | awk '$NF=="/"{printf "Disk Usage: %d/%dGB (%s)\n", $3,$2,$5}')\033[0m"
    echo -e "\033[0;32m=====================================\033[0m"
    echo -e "\033[1;32mSystem Information\033[0m"
    echo -e "-------------------------------------"
    echo -e "Machine Name: \033[1;33m$(hostname)\033[0m"

    IP_ADDRESS=""
    if command -v ip &> /dev/null; then
        IP_ADDRESS=$(ip -4 addr show scope global | grep inet | awk '{print $2}' | cut -d/ -f1 | head -n 1)
    elif command -v ifconfig &> /dev/null; then
        IP_ADDRESS=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -n 1)
    fi
    echo -e "IP Address: \033[1;33m${IP_ADDRESS:-(Not Found)}\033[0m"

    echo -e "Default Gateway: \033[1;33m$(ip route | grep default | awk '{print $3}')\033[0m"
    echo -e "-------------------------------------"
    echo -e "\033[1;32mOptions\033[0m"
    echo -e "-------------------------------------"
    echo -e "\033[1;36m1.\033[0m WordPress"
    echo -e "\033[1;36m2.\033[0m Xen Orchestra"
    echo -e "\033[1;36m3.\033[0m UniFi Controller"
    echo -e "\033[1;36m4.\033[0m CloudFlare Tunnels"
    echo -e "\033[1;36m9.\033[0m Return to Main Menu/Exit"
    echo -e "\033[0;32m=====================================\033[0m"
}

# Function to execute sibling scripts
execute_installerScript() {
    local script_name=$1
    
    if [ -f "$script_name" ]; then
        echo "Executing $script_name..."
        bash "$script_name"
        
        # BUG FIX: Moved the pause logic INSIDE the function.
        # It only asks you to return AFTER you have run a script.
        # This prevents the loop from getting stuck when you try to exit.
        echo ""
        read -p "Press [Enter] to return to menu or type 'exit' to exit: " next_action
        if [ "$next_action" = "exit" ]; then
            exit 0
        fi
    else
        echo -e "\033[0;31mError: Script '$script_name' not found in $SCRIPT_DIR\033[0m"
        read -p "Press [Enter] to continue..."
    fi
}

# Main loop
while true; do
    show_menu
    read -p "Enter your choice [1-4]: " choice
    case $choice in
        1)
            echo "You have selected WordPress"
            execute_installerScript "WordPress.sh"
            ;;
        2)
            echo "You have selected Xen Orchestra"
            execute_installerScript "XenOrchestra.sh"
            ;;
        3)
            echo "You have selected UniFi Controller"
            execute_installerScript "UniFi-Controller.sh"
            ;;
        4)
            echo "You have selected CloudFlare Tunnels"
            execute_installerScript "CloudFlare-Tunnels.sh"
            ;;
        9)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo -e "\033[0;31mInvalid option. Please choose a number between 1 and 4, or 9 to exit.\033[0m"
            sleep 2
            ;;
    esac
    
    # BUG FIX: Removed the logic block that used to be here.
    # The loop now cycles cleanly.
done
