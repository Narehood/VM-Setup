#!/bin/bash

# Function to detect the system name
get_system_name() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        SYSTEM_NAME=$NAME
    else
        SYSTEM_NAME=$(uname -s)
    fi
}

# Function to display the menu
show_menu() {
    clear
    get_system_name
    echo -e "====================================="
    echo -e "          \e[1;34mVM Setup Menu 1.4.2\e[0m"
    echo -e "====================================="
    echo -e "\e[1;32mSystem Information\e[0m"
    echo -e "-------------------------------------"
    echo -e "System Name: \e[1;33m$SYSTEM_NAME\e[0m"
    echo -e "Linux Distribution: \e[1;33m$(lsb_release -d | cut -f2)\e[0m"
    echo -e "Kernel Version: \e[1;33m$(uname -r)\e[0m"
    echo -e "CPU Usage: \e[1;33m$(top -bn1 | grep 'Cpu(s)' | sed 's/.*, *\([0-9.]*\)%* id.*/\1/' | awk '{print 100 - $1"%"}')\e[0m"
    echo -e "Memory Usage: \e[1;33m$(free -m | awk 'NR==2{printf "Memory Usage: %s/%sMB (%.2f%%)\n", $3,$2,$3*100/$2 }')\e[0m"
    echo -e "Disk Usage: \e[1;33m$(df -h | awk '$NF=="/"{printf "Disk Usage: %d/%dGB (%s)\n", $3,$2,$5}')\e[0m"
    echo -e "-------------------------------------"
    echo -e "\e[1;32mOptions\e[0m"
    echo -e "-------------------------------------"
    echo -e "\e[1;36m1.\e[0m XCP-NG / Virtual Machine Initial Configuration"
    echo -e "\e[1;36m2.\e[0m Xen Orchestra"
    echo -e "\e[1;36m3.\e[0m UniFi Controller"
    echo -e "\e[1;36m4.\e[0m Docker Host Prep"
    echo -e "\e[1;36m5.\e[0m Enable Automated Security Patches"
    echo -e "\e[1;36m6.\e[0m Check for System Updates"    
    echo -e "\e[1;36m7.\e[0m Check for Menu Updates"
    echo -e "\e[1;36m8.\e[0m Exit"
    echo -e "====================================="
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

# Main loop
while true; do
    show_menu
    read -p "Enter your choice [1-8]: " choice
    case $choice in
        1)
            echo "You have selected XCP-NG / Virtual Machine Initial Configuration"
            cd Installers/
            bash serverSetup.sh
            ;;
        2)
            echo "You have selected Xen Orchestra"
            cd Installers/
            bash XenOrchestra.sh
            ;;
        3)
            echo "You have selected UniFi Controller"
            cd Installers/
            bash UniFi-Controller
