#!/bin/bash

# Function to display the menu
show_menu() {
    clear
    echo -e "\033[0;32m=====================================\033[0m"
    echo -e "          \033[1;34mVM Setup Menu 2.1.2\033[0m"
    echo -e "\033[0;32m=====================================\033[0m"
    echo -e "\033[1;32mResource Information\033[0m"
    echo -e "-------------------------------------"
    echo -e "Linux Distribution: \033[1;33m$(lsb_release -d | cut -f2)\033[0m"
    echo -e "Kernel Version: \033[1;33m$(uname -r)\033[0m"
    echo -e "CPU Usage: \033[1;33m$(top -bn1 | grep 'Cpu(s)' | sed 's/.*, *\([0-9.]*\)%* id.*/\1/' | awk '{print 100 - $1"%"}')\033[0m"
    echo -e "Memory Usage: \033[1;33m$(free -m | awk 'NR==2{printf "Memory Usage: %s/%sMB (%.2f%%)\n", $3,$2,$3*100/$2 }')\033[0m"
    echo -e "Disk Usage: \033[1;33m$(df -h | awk '$NF=="/"{printf "Disk Usage: %d/%dGB (%s)\n", $3,$2,$5}')\033[0m"
    echo -e "\033[0;32m=====================================\033[0m"
    echo -e "\033[1;32mSystem Information\033[0m"
    echo -e "-------------------------------------"
    echo -e "Machine Name: \033[1;33m$(hostname)\033[0m"
    echo -e "IP Address: \033[1;33m$(hostname -I | awk '{print $1}')\033[0m"
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
    echo -e "\033[1;36m9.\033[0m Exit"
    echo -e "\033[0;32m=====================================\033[0m"
}

# Function to check for updates in the repository
check_for_updates() {
    echo "Checking for updates in VM-Setup repository..."
    git remote update
    LOCAL=$(git rev-parse @)
    REMOTE=$(git rev-parse @{u})
    if [ "$LOCAL" = "$REMOTE" ]; then
        echo "VM-Setup is up to date."
    else
        echo "VM-Setup has updates available."
        read -p "Do you want to pull the latest changes? (y/n): " pull_choice
        if [ "$pull_choice" = "y" ]; then
            git pull
            echo "Repository updated successfully."
            bash install.sh
        else
            echo "Update aborted."
        fi
    fi
}

# Function to navigate to installers and execute a script
execute_installerScript() {
    local script_name=$1
    cd Installers/
    bash "$script_name"
}

# Main loop
while true; do
    show_menu
    read -p "Enter your choice [1-6]: " choice
    case $choice in
        1)
            echo "You have selected XCP-NG / Virtual Machine Initial Configuration"
            execute_installerScript "serverSetup.sh"
            ;;
        2)
            echo "You have selected Other Installers"
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
            echo "Checking for updates..."
            check_for_updates
            ;;
        9)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo -e "\033[0;31mInvalid option. Please choose a number between 1 and 8.\033[0m"
            ;;
    esac
    if [ "$choice" -ne 9 ]; then
        read -p "Press [Enter] key to return to menu or type 'exit' to exit: " next_action
        if [ "$next_action" = "exit" ]; then
            exit 0
        fi
    fi
done
