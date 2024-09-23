#!/bin/bash

# Function to display the menu
show_menu() {
    clear
    echo "====================================="
    echo "          VM Setup Menu"
    echo "====================================="
    echo "1. XCP-NG Initial Configuration"
    echo "2. Xen Orchestra"
    echo "3. UniFi Controller"
    echo "4. Docker Host Prep"
    echo "5. Check for Updates"
    echo "6. Exit"
    echo "====================================="
}

# Function to display system information
show_system_info() {
    echo "====================================="
    echo "          System Information"
    echo "====================================="
    echo "Linux Distribution: $(lsb_release -d | cut -f2)"
    echo "Kernel Version: $(uname -r)"
    echo "CPU Usage: $(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')"
    echo "Memory Usage: $(free -m | awk 'NR==2{printf "Memory Usage: %s/%sMB (%.2f%%)\n", $3,$2,$3*100/$2 }')"
    echo "Disk Usage: $(df -h | awk '$NF=="/"{printf "Disk Usage: %d/%dGB (%s)\n", $3,$2,$5}')"
    echo "====================================="
}

# Function to check for updates
check_for_updates() {
    local repo_url="https://github.com/Narehood/VM-Setup"
    local local_file="/VM-Setup/install.sh"
    local remote_file="https://raw.githubusercontent.com/Narehood/VM-Setup/main/install.sh"

    # Download the remote file to a temporary location
    curl -s -o /tmp/install.sh $remote_file

    # Compare the local and remote files
    if ! cmp -s $local_file /tmp/install.sh; then
        echo "A new version of install.sh is available."
        read -p "Do you want to update? [y/n]: " update_choice
        if [[ $update_choice == "y" || $update_choice == "Y" ]]; then
            echo "Updating install.sh..."
            mv /tmp/install.sh $local_file
            chmod +x $local_file
            echo "Running the updated install.sh..."
            $local_file
        else
            echo "Update canceled."
        fi
    else
        echo "install.sh is up to date."
    fi

    # Clean up the temporary file
    rm -f /tmp/install.sh
}

while true; do
    show_system_info
    show_menu
    read -p "Enter your choice [1-6]: " choice

    case $choice in
        1)
            echo "You chose XCP-NG Initial Configuration"
            git clone https://github.com/your-repo/xcp-ng-setup.git /VM-Setup/xcp-ng-setup
            cd /VM-Setup/xcp-ng-setup
            ;;
        2)
            echo "You chose Xen Orchestra"
            git clone https://github.com/your-repo/xen-orchestra-setup.git /VM-Setup/xen-orchestra-setup
            cd /VM-Setup/xen-orchestra-setup
            ;;
        3)
            echo "You chose UniFi Controller"
            git clone https://github.com/your-repo/unifi-controller-setup.git /VM-Setup/unifi-controller-setup
            cd /VM-Setup/unifi-controller-setup
            ;;
        4)
            echo "You chose Docker Host Prep"
            git clone https://github.com/your-repo/docker-host-prep.git /VM-Setup/docker-host-prep
            cd /VM-Setup/docker-host-prep
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
