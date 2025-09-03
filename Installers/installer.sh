#!/bin/bash

# Function to display the menu
show_menu() {
    clear
    echo -e "\033[0;32m=====================================\033[0m"
    echo -e "          \033[1;34mVM Setup Installer Menu\033[0m"
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
    echo -e "\033[1;36m1.\033[0m WordPress"
    echo -e "\033[1;36m2.\033[0m Xen Orchestra"
    echo -e "\033[1;36m3.\033[0m UniFi Controller"
    echo -e "\033[1;36m4.\033[0m Pterodactyl"
    echo -e "\033[1;36m5.\033[0m CloudFlare Tunnels"
    echo -e "\033[1;36m9.\033[0m Exit"
    echo -e "\033[0;32m=====================================\033[0m"
}

# Function to navigate to installers and execute a script
execute_installerScript() {
    local script_name=$1
    bash "$script_name"
}

# Main loop
while true; do
    show_menu
    read -p "Enter your choice [1-3]: " choice
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
            echo "You have selected Pterodactyl"
            execute_installerScript "Pterodactyl.sh"
            ;;
        5)
            echo "You have selected CloudFlare Tunnels"
            execute_installerScript "CloudFlare-Tunnels.sh"
            ;;
        9)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo -e "\033[0;31mInvalid option. Please choose a number between 1 and 5, or 9 to exit.\033[0m"
            ;;
    esac
    if [ "$choice" -ne 9 ]; then
        read -p "Press [Enter] key to return to menu or type 'exit' to exit: " next_action
        if [ "$next_action" = "exit" ]; then
            exit 0
        fi
    fi
done
