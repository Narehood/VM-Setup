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
echo -e "${CYAN}                  NEWT VPN NODE SETUP                      ${NC}"
echo -e "${BLUE}===================================================================${NC}"
echo ""

# DEPENDENCY CHECK (AUTO-INSTALL CURL)
echo -e "${CYAN}[INFO]${NC} Checking for required dependencies..."

if ! command -v curl &> /dev/null; then
    echo -e "${YELLOW}[WARN]${NC} 'curl' is missing. Attempting to install..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            debian|ubuntu|kali|linuxmint)
                sudo apt update -q && sudo apt install -y curl ;;
            fedora|rhel|centos|rocky|almalinux)
                sudo dnf install -y curl ;;
            arch|manjaro)
                sudo pacman -S --noconfirm curl ;;
            alpine)
                sudo apk add curl ;;
            opensuse*|suse)
                sudo zypper install -y curl ;;
            *)
                echo -e "${RED}[ERROR]${NC} Could not auto-install curl. Please install it manually."
                exit 1 ;;
        esac
        echo -e "${GREEN}[SUCCESS]${NC} Curl installed."
    else
        echo -e "${RED}[ERROR]${NC} OS not detected. Cannot install curl."
        exit 1
    fi
else
    echo -e "${GREEN}[OK]${NC} Dependencies met."
fi

# INSTALLATION
echo -e "\n${CYAN}[INFO]${NC} Downloading and installing Newt binary..."

if curl -fsSL https://pangolin.net/get-newt.sh | bash; then
    echo -e "${GREEN}[SUCCESS]${NC} Newt binary installed."
else
    echo -e "${RED}[ERROR]${NC} Failed to download/install Newt from pangolin.net."
    exit 1
fi

# Verify installation path (script usually puts it in /usr/local/bin or current dir)
# We assume the get-newt.sh puts it in the path or we need to find it.
# If the script puts it in current dir, we move it to /usr/local/bin for global service usage.
if [ -f "./newt" ]; then
    echo -e "${CYAN}[INFO]${NC} Moving binary to /usr/local/bin..."
    sudo mv ./newt /usr/local/bin/newt
    sudo chmod +x /usr/local/bin/newt
fi

if ! command -v newt &> /dev/null; then
    # Fallback check
    if [ -f "/usr/local/bin/newt" ]; then
        echo -e "${GREEN}[OK]${NC} Binary confirmed at /usr/local/bin/newt."
    else
        echo -e "${RED}[ERROR]${NC} Newt command not found. Installation might have failed."
        exit 1
    fi
fi

# CONFIGURATION INPUT
echo -e "\n${WHITE}--- NODE CONFIGURATION ---${NC}"
echo "Please enter the credentials provided by your controller."
echo ""

read -p "Enter Node ID: " NEWT_ID
read -p "Enter Secret: " NEWT_SECRET
read -p "Enter Endpoint URL (e.g., https://auth.qutzl.net): " NEWT_ENDPOINT

# Validate inputs
if [[ -z "$NEWT_ID" || -z "$NEWT_SECRET" || -z "$NEWT_ENDPOINT" ]]; then
    echo -e "\n${RED}[ERROR]${NC} All fields are required. Setup aborted."
    exit 1
fi

# SERVICE CREATION
echo -e "\n${CYAN}[INFO]${NC} Creating systemd service..."

SERVICE_FILE="/etc/systemd/system/newt.service"

# Create the service file using heredoc
sudo bash -c "cat > $SERVICE_FILE" <<EOF
[Unit]
Description=Newt VPN Client
After=network.target

[Service]
ExecStart=/usr/local/bin/newt --id $NEWT_ID --secret $NEWT_SECRET --endpoint $NEWT_ENDPOINT
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

if [ -f "$SERVICE_FILE" ]; then
    echo -e "${GREEN}[OK]${NC} Service file created at $SERVICE_FILE"
else
    echo -e "${RED}[ERROR]${NC} Failed to write service file."
    exit 1
fi

# ENABLE AND START
echo -e "${CYAN}[INFO]${NC} Enabling and starting service..."

sudo systemctl daemon-reload
sudo systemctl enable newt
sudo systemctl start newt

# Give it a moment to initialize
sleep 2

# Check status
if systemctl is-active --quiet newt; then
    echo -e "\n${GREEN}[SUCCESS]${NC} Newt VPN is RUNNING."
    echo -e "You can check logs with: ${YELLOW}sudo journalctl -u newt -f${NC}"
else
    echo -e "\n${RED}[ERROR]${NC} Newt service failed to start."
    echo "Check status with: sudo systemctl status newt"
fi

echo ""
read -p "Press [Enter] to finish..."
