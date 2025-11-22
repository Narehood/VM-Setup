#!/bin/bash
# This prevents "file not found" errors if you run the script from a different folder.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || { echo "Failed to change directory to $SCRIPT_DIR"; exit 1; }

# Function to display the menu
show_menu() {
    clear
    echo -e "\033[0;32m=====================================\033[0m"
    echo -e "          \033[1;34mVM Setup Menu 2.6.0\033[0m"
    echo -e "\033[0;32m=====================================\033[0m"
    echo -e "\033[1;32mResource Information\033[0m"
    echo -e "-------------------------------------"

    # Adapt for Alpine: lsb_release is not available by default
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

    # 2. CPU FIX: Use /proc/stat for a more accurate instant reading than 'top -bn1'
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
    echo -e "\033[1;36m1.\033[0m XCP-NG / Virtual Machine Initial Configuration"
    echo -e "\033[1;36m2.\033[0m Installer Scripts"
    echo -e "\033[1;36m3.\033[0m Docker Host Prep"
    echo -e "\033[1;36m4.\033[0m Enable Automated Security Patches"
    echo -e "\033[1;36m5.\033[0m Check for System Updates"
    echo -e "\033[1;36m6.\033[0m Check for Menu Updates"
    echo -e "\033[1;36m7.\033[0m Launch Linux Utility"
    echo -e "\033[1;36m9.\033[0m Exit"
    echo -e "\033[0;32m=====================================\033[0m"
}

# Function to check for updates in the repository
check_for_updates() {
    echo "Checking for updates in VM-Setup repository..."
    
    # Fetch updates without merging
    git fetch
    
    LOCAL=$(git rev-parse @)
    # 3. GIT FIX: Gracefully handle cases where upstream isn't configured
    if ! REMOTE=$(git rev-parse @{u} 2>/dev/null); then
        echo -e "\033[0;31mError: No upstream branch configured. Cannot check for updates.\033[0m"
        read -p "Press [Enter] to continue..."
        return
    fi

    if [ "$LOCAL" = "$REMOTE" ]; then
        echo "VM-Setup is up to date."
        read -p "Press [Enter] to continue..."
    else
        echo "VM-Setup has updates available."
        read -p "Do you want to pull the latest changes? (y/n): " pull_choice
        if [ "$pull_choice" = "y" ]; then
            git pull
            echo "Repository updated successfully."
            echo "Restarting menu..."
            sleep 1
            # 4. RESTART FIX: Replace the current process with the updated script
            exec "$0" "$@"
        else
            echo "Update aborted."
        fi
    fi
}

# Function to navigate to installers and execute a script
execute_installerScript() {
    local script_name=$1
    # Since we set SCRIPT_DIR at the top, we can trust relative paths now
    if [ -d "Installers" ]; then
        if [ -f "Installers/$script_name" ]; then
            echo "Executing $script_name..."
            bash "Installers/$script_name"
        else
            echo "Error: Installer script 'Installers/$script_name' not found."
            read -p "Press [Enter] to continue..."
        fi
    else
        echo "Error: 'Installers' directory not found."
        read -p "Press [Enter] to continue..."
    fi
}

# Main loop
while true; do
    show_menu
    read -p "Enter your choice [1-7]: " choice
    case $choice in
        1)
            echo "You have selected XCP-NG / Virtual Machine Initial Configuration"
            execute_installerScript "serverSetup.sh"
            ;;
        2)
            echo "You have selected Installer Scripts"
            execute_installerScript "installer.sh"
            ;;
        3)
            echo "You have selected Docker Host Prep"
            execute_installerScript "Docker-Prep.sh"
            ;;
        4)
            echo "You have selected Enable Automated Security Patches"
            execute_installerScript "Automated-Security-Patches.sh"
            ;;
        5)
            echo "You have selected System Update"
            execute_installerScript "systemUpdate.sh"
            ;;
        6)
            echo "Checking for menu updates..."
            check_for_updates
            ;;
        7)
            echo "Launching LinUtil..."
            execute_installerScript "linutil.sh"
            ;;
        9)
            echo "Exiting..."
            exit 0
            ;;
        *)
            # 5. TYPO FIX: Updated to reflect 1-7
            echo -e "\033[0;31mInvalid option. Please choose a number between 1 and 7, or 9 to exit.\033[0m"
            sleep 2
            ;;
    esac
    
    if [ "$choice" -ne 9 ] && [ "$choice" -ne 6 ]; then
        read -p "Press [Enter] key to return to menu or type 'exit' to exit: " next_action
        if [ "$next_action" = "exit" ]; then
            exit 0
        fi
    fi
done
