#!/bin/bash

# Function to display the menu
show_menu() {
    clear
    echo -e "====================================="
    echo -e "          \e[1;34mVM Setup Menu 1.0.0\e[0m"
    echo -e "====================================="
    echo -e "\e[1;32mSystem Information\e[0m"
    echo -e "-------------------------------------"
    echo -e "Linux Distribution: \e[1;33m$(lsb_release -d | cut -f2)\e[0m"
    echo -e "Kernel Version: \e[1;33m$(uname -r)\e[0m"
    echo -e "CPU Usage: \e[1;33m$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')\e[0m"
    echo -e "Memory Usage: \e[1;33m$(free -m | awk 'NR==2{printf "Memory Usage: %s/%sMB (%.2f%%)\n", $3,$2,$3*100/$2 }')\e[0m"
    echo -e "Disk Usage: \e[1;33m$(df -h | awk '$NF=="/"{printf "Disk Usage: %d/%dGB (%s)\n", $3,$2,$5}')\e[0m"
    echo -e "-------------------------------------"
    echo -e "\e[1;32mOptions\e[0m"
    echo -e "-------------------------------------"
    echo -e "\e[1;36m1.\e[0m XCP-NG / Virtual Machine Initial Configuration"
    echo -e "\e[1;36m2.\e[0m Xen Orchestra"
    echo -e "\e[1;36m3.\e[0m UniFi Controller"
    echo -e "\e[1;36m4.\e[0m Docker Host Prep"
    echo -e "\e[1;36m5.\e[0m Check for Updates (Coming Soon)"
    echo -e "\e[1;36m6.\e[0m Exit"
    echo -e "====================================="
}

while true; do
    show_menu
    read -p "Enter your choice [1-6]: " choice

    case $choice in
        1)
            echo "You chose XCP-NG/Virtual Machine Initial Configuration"
            cd Installers/
            bash serverSetup.sh
            ;;
        2)
            echo "You chose Xen Orchestra"
            cd Installers/
            bash XenOrchestra.sh
            ;;
        3)
            echo "You chose UniFi Controller"
            cd Installers/
            bash UniFi-Controller.sh
            ;;
        4)
            echo "You chose Docker Host Prep"
            cd VM-Setup/Installers/
            cd Installers/
            bash install.sh
            ;;
        5)
            echo "Check for Updates feature is coming soon!"
            ;;
        6)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid option. Please choose a number between 1 and 6."
            ;;
    esac
done
