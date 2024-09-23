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
    echo -e "\e[1;36m5.\e[0m Check for Updates"
    echo -e "\e[1;36m6.\e[0m Exit"
    echo -e "====================================="
}

# Function to check for updates
check_for_updates() {
    local repo_url="https://github.com/Narehood/VM-Setup"
    local local_dir="/VM-Setup"
    local temp_dir="/tmp/VM-Setup"

    # Clone the remote repository to a temporary location
    git clone $repo_url $temp_dir

    # Compare the local and remote directories
    if ! diff -qr $local_dir $temp_dir > /dev/null; then
        echo "A new version of the VM-Setup repository is available."
        read -p "Do you want to update? [y/n]: " update_choice
        if [[ $update_choice == "y" || $update_choice == "Y" ]]; then
            echo "Updating VM-Setup..."
            rm -rf $local_dir
            mv $temp_dir $local_dir
            echo "VM-Setup has been updated."
        else
            echo "Update canceled."
            rm -rf $temp_dir
        fi
    else
        echo "VM-Setup is up to date."
        rm -rf $temp_dir
    fi
}

while true; do
    show_menu
    read -p "Enter your choice [1-6]: " choice

    case $choice in
        1)
            echo "You chose XCP-NG/Virtual Machine Initial Configuration"
            bash serverSetup.sh
            ;;
        2)
            echo "You chose Xen Orchestra"
            cd VM-Setup/Installers
            bash XenOrchestra.sh
            ;;
        3)
            echo "You chose UniFi Controller"
            cd VM-Setup/Installers/UniFi-Controller.sh
            ;;
        4)
            echo "You chose Docker Host Prep"
            git clone https://github.com/Narehood/Docker-Prep.git
            cd Docker-Prep
            bash install.sh
            ;;
        5)
            echo "Checking for updates..."
            check_for_updates
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
