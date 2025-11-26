#!/bin/bash

# --- 1. VISUAL STYLING ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# --- 2. HEADER ---
clear
echo -e "${BLUE}===================================================================${NC}"
echo -e "${CYAN}                PANGOLIN TUNNEL INSTALLER                  ${NC}"
echo -e "${BLUE}===================================================================${NC}"
echo ""

# --- 3. DEPENDENCY CHECK (AUTO-INSTALL CURL) ---
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
        echo -e "${GREEN}[SUCCESS]${NC} Curl installed."
    else
        echo -e "${RED}[ERROR]${NC} OS not detected. Cannot install curl."
        exit 1
    fi
else
    echo -e "${GREEN}[OK]${NC} Dependencies met."
fi

# --- 4. EXECUTION ---
echo -e "\n${CYAN}[INFO]${NC} Downloading installer manifest..."

# Download and execute the fetch script
if curl -fsSL https://pangolin.net/get-installer.sh | bash; then
    echo -e "${GREEN}[OK]${NC} Installer manifest processed."
else
    echo -e "${RED}[ERROR]${NC} Failed to download get-installer.sh from pangolin.net."
    exit 1
fi

echo -e "\n${CYAN}[INFO]${NC} Launching Pangolin Installer..."
sleep 1

# Check if the binary was actually created
if [ -f "./installer" ]; then
    # Make executable just in case
    chmod +x ./installer
    
    # Run the binary
    if sudo ./installer; then
        echo -e "\n${GREEN}[SUCCESS]${NC} Pangolin installation complete."
        
        # Cleanup
        echo -e "${CYAN}[INFO]${NC} Cleaning up temporary files..."
        rm -f ./installer
    else
        echo -e "\n${RED}[ERROR]${NC} The installer exited with an error."
        exit 1
    fi
else
    echo -e "\n${RED}[ERROR]${NC} The 'installer' binary was not found."
    echo "The get-installer.sh script may have failed silently or changed behavior."
    exit 1
fi
