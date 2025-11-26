#!/bin/bash

# VISUAL STYLING
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# HEADER
clear
echo -e "${BLUE}===================================================================${NC}"
echo -e "${CYAN}             CLOUDFLARE TUNNEL (CLOUDFLARED) SETUP         ${NC}"
echo -e "${BLUE}===================================================================${NC}"
echo ""

# ROOT CHECK
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR]${NC} Please run as root (use sudo)."
    exit 1
fi

# OS DETECTION
echo -e "${CYAN}[INFO]${NC} Detecting Operating System..."
OS_FAMILY=""
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
        debian|ubuntu|kali|linuxmint|pop)
            OS_FAMILY="debian" ;;
        fedora|rhel|centos|rocky|almalinux)
            OS_FAMILY="rhel" ;;
        arch|manjaro)
            OS_FAMILY="arch" ;;
        alpine)
            OS_FAMILY="alpine" ;;
        *)
            echo -e "${RED}[ERROR]${NC} Unsupported OS: $ID"
            exit 1 ;;
    esac
    echo -e "${GREEN}[OK]${NC} Detected: $ID ($OS_FAMILY)"
else
    echo -e "${RED}[ERROR]${NC} Could not detect OS."
    exit 1
fi

# INSTALLATION FUNCTIONS

install_debian() {
    echo -e "${CYAN}[INFO]${NC} Setting up Cloudflare repository..."
    mkdir -p --mode=0755 /usr/share/keyrings
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null

    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" | tee /etc/apt/sources.list.d/cloudflared.list >/dev/null

    echo -e "${CYAN}[INFO]${NC} Installing cloudflared..."
    apt-get update -q
    apt-get install -y cloudflared -q
}

install_rhel() {
    echo -e "${CYAN}[INFO]${NC} Setting up Cloudflare repository..."
    curl -fsSL https://pkg.cloudflare.com/cloudflared-ascii.repo | tee /etc/yum.repos.d/cloudflared.repo >/dev/null

    echo -e "${CYAN}[INFO]${NC} Installing cloudflared..."
    if command -v dnf >/dev/null; then
        dnf install -y cloudflared -q
    else
        yum install -y cloudflared -q
    fi
}

install_arch() {
    echo -e "${CYAN}[INFO]${NC} Installing cloudflared via Pacman..."
    pacman -S --noconfirm cloudflared
}

install_alpine() {
    echo -e "${CYAN}[INFO]${NC} Installing cloudflared via APK..."
    # Cloudflared is in the community repo
    apk update
    apk add cloudflared
}

# EXECUTE INSTALL

# Check if already installed
if command -v cloudflared &> /dev/null; then
    echo -e "${YELLOW}[WARN]${NC} 'cloudflared' is already installed."
    read -p "Re-install/Update? (y/N): " reinstall
    if [[ "$reinstall" =~ ^[Yy]$ ]]; then
        case "$OS_FAMILY" in
            debian) install_debian ;;
            rhel)   install_rhel ;;
            arch)   install_arch ;;
            alpine) install_alpine ;;
        esac
    fi
else
    # Install
    case "$OS_FAMILY" in
        debian) install_debian ;;
        rhel)   install_rhel ;;
        arch)   install_arch ;;
        alpine) install_alpine ;;
    esac
fi

# Verify Installation
if ! command -v cloudflared &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} Installation failed. 'cloudflared' binary not found."
    exit 1
fi
echo -e "${GREEN}[SUCCESS]${NC} Cloudflared installed successfully."

# TOKEN CONFIGURATION
echo ""
echo -e "${WHITE}--- TUNNEL CONFIGURATION ---${NC}"
echo "1. Go to Cloudflare Zero Trust Dashboard > Networks > Tunnels"
echo "2. Create a new tunnel (or select existing) and click 'Configure'"
echo "3. Copy the token (it looks like a long base64 string)"
echo ""

read -p "Paste your Tunnel Token (or press Enter to skip): " CF_TOKEN

if [ -n "$CF_TOKEN" ]; then
    echo -e "\n${CYAN}[INFO]${NC} Installing system service..."
    
    # Run the service install command
    cloudflared service install "$CF_TOKEN"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[SUCCESS]${NC} Service installed and started."
        echo -e "Check status with: ${YELLOW}systemctl status cloudflared${NC}"
    else
        echo -e "${RED}[ERROR]${NC} Failed to install service. Check the token and try again."
    fi
else
    echo -e "${YELLOW}[SKIP]${NC} No token provided."
    echo "You can configure it later using:"
    echo "sudo cloudflared service install <token>"
fi

echo ""
read -p "Press [Enter] to finish..."
