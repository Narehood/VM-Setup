#!/bin/bash

# Function to display the menu
show_menu() {
    clear
    echo -e "====================================="
    echo -e "          \e[1;34mVM Setup Menu 1.2.0\e[0m"
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
    echo -e "\e[1;36m5.\e[0m Enable Automated Security Patches"    
    echo -e "\e[1;36m6.\e[0m Check for Updates (Coming Soon)"
    echo -e "\e[1;36m7.\e[0m Exit"
    echo -e "====================================="
}

while true; do
    show_menu
    read -p "Enter your choice [1-6]: " choice

    case $choice in
        1)
            echo "You have selected XCP-NG/Virtual Machine Initial Configuration"
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
            bash UniFi-Controller.sh
            ;;
        4)
            echo "You haved selected Docker Host Prep"
            cd VM-Setup/Installers/
            cd Installers/
            bash Docker-Prep.sh
            ;;
        5)
            echo "You haved selected Docker Host Prep"
            cd VM-Setup/Installers/
            cd Installers/
            bash Automated-Security-Patches.sh
            ;;            
        6)
            echo "Check for Updates feature is coming soon!"
            ;;
        7)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid option. Please choose a number between 1 and 6."
            ;;
    esac
done
