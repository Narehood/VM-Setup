#!/bin/bash

# VISUAL STYLING
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# HEADER
clear
echo -e "${BLUE}===================================================================${NC}"
echo -e "${CYAN}                  CHRIS TITUS TECH  |  LINUTIL LAUNCHER            ${NC}"
echo -e "${BLUE}===================================================================${NC}"
echo ""

# DEPENDENCY CHECK
# LinUtil requires curl to download.
echo -e "${CYAN}[INFO]${NC} Checking for required dependencies..."

if ! command -v curl &> /dev/null; then
    echo -e "${YELLOW}[WARN]${NC} 'curl' is missing. Attempting to install..."
    
    # Detect Package Manager and install curl
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            debian|ubuntu|kali|linuxmint)
                sudo apt update -q && sudo apt install -y curl
                ;;
            fedora|rhel|centos|rocky|almalinux)
                sudo dnf install -y curl
                ;;
            arch|manjaro)
                sudo pacman -S --noconfirm curl
                ;;
            alpine)
                sudo apk add curl
                ;;
            opensuse*|suse)
                sudo zypper install -y curl
                ;;
            *)
                echo -e "${RED}[ERROR]${NC} Could not auto-install curl. Please install it manually."
                read -p "Press [Enter] to exit..."
                exit 1
                ;;
        esac
    fi
else
    echo -e "${GREEN}[OK]${NC} Dependencies met."
fi

# EXECUTION
echo ""
echo -e "${WHITE}About to launch: ${YELLOW}christitus.com/linux${NC}"
echo -e "This will download and run the LinUtil script directly from the internet."
echo ""
read -p "Press [Enter] to continue or Ctrl+C to cancel..."

echo -e "\n${GREEN}>>> Launching LinUtil...${NC}"
sleep 1

# Execute the script
curl -fsSL https://christitus.com/linux | sh

# The script typically clears the screen on exit, so we just exit cleanly here.
exit 0
