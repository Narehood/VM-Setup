#!/bin/bash

# --- Configuration Variables ---
WORKGROUP_NAME="WORKGROUP"  # Change this if your Windows workgroup is different
SERVER_HOSTNAME=$(hostname) # Automatically gets your server's hostname

# --- Functions ---
log_message() {
    echo "--- $(date +'%Y-%m-%d %H:%M:%S') --- $1"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_message "Error: This script must be run as root."
        log_message "Please run with: sudo ./setup_samba_visibility.sh"
        exit 1
    fi
}

# --- Main Script ---
check_root

log_message "Starting Samba setup for workgroup visibility..."

log_message "Updating package list..."
sudo apt update || { log_message "Failed to update package list. Exiting."; exit 1; }

log_message "Installing Samba..."
sudo apt install -y samba || { log_message "Failed to install Samba. Exiting."; exit 1; }

log_message "Backing up existing smb.conf (if any)..."
if [ -f "/etc/samba/smb.conf" ]; then
    sudo cp /etc/samba/smb.conf "/etc/samba/smb.conf.backup_$(date +%Y%m%d_%H%M%S)"
    log_message "Backed up to /etc/samba/smb.conf.backup_$(date +%Y%m%d_%H%M%S)"
fi

log_message "Creating new smb.conf with workgroup visibility settings..."
cat << EOF | sudo tee /etc/samba/smb.conf > /dev/null
[global]
   workgroup = ${WORKGROUP_NAME}
   netbios name = ${SERVER_HOSTNAME}
   server string = %h server (Samba, Ubuntu)
   server role = standalone server
   name resolve order = bcast host lmhosts wins

   client min protocol = SMB2
   server min protocol = SMB2

   log file = /var/log/samba/log.%m
   max log size = 1000
   logging = file
   panic action = /usr/share/samba/panic-action %d

   obey pam restrictions = yes
   unix password sync = yes
   passwd program = /usr/bin/passwd %u
   passwd chat = *Enter\\snew\\s*\\spassword:* %n\\n *Retype\\snew\\s*\\spassword:* %n\\n *password\\supdated\\ssuccessfully* .
   pam password change = yes
   map to guest = bad user

   usershare allow guests = yes

[printers]
   comment = All Printers
   browseable = no
   path = /var/tmp
   printable = yes
   guest ok = no
   read only = yes
   create mask = 0700

[print\$]
   comment = Printer Drivers
   path = /var/lib/samba/printers
   browseable = yes
   read only = yes
   guest ok = no
EOF
log_message "smb.conf created successfully."

log_message "Checking Samba configuration with testparm..."
# testparm outputs to stderr, so redirect to stdout for logging
sudo testparm 2>&1 | tee -a /tmp/samba_testparm_output.log
if grep -q "Loaded services file OK" /tmp/samba_testparm_output.log; then
    log_message "testparm reports configuration is OK."
else
    log_message "testparm found issues with smb.conf. Please check /tmp/samba_testparm_output.log for details."
    log_message "Samba services might not start. Exiting."
    exit 1
fi
rm /tmp/samba_testparm_output.log

log_message "Configuring UFW (Uncomplicated Firewall) to allow Samba..."
sudo ufw allow samba || { log_message "Failed to add Samba UFW rule. Check UFW status."; exit 1; }
sudo ufw reload || { log_message "Failed to reload UFW. Exiting."; exit 1; }
log_message "UFW configured."

log_message "Restarting Samba services..."
sudo systemctl restart smbd nmbd || { log_message "Failed to restart smbd and nmbd. Check logs with 'sudo journalctl -xe | grep smbd' and 'sudo journalctl -xe | grep nmbd'."; exit 1; }

log_message "Verifying Samba service status..."
sudo systemctl status smbd | grep "Active:"
sudo systemctl status nmbd | grep "Active:"
sudo systemctl status samba.service | grep "Active:"

if sudo systemctl is-active --quiet smbd && \
   sudo systemctl is-active --quiet nmbd && \
   sudo systemctl is-active --quiet samba.service; then
    log_message "Samba services are running successfully."
    log_message "Setup complete! Your server '${SERVER_HOSTNAME}' should now be visible in the '${WORKGROUP_NAME}' workgroup."
    log_message "You may need to wait a few minutes and refresh your Windows File Explorer 'Network' view."
    log_message "To share files, you'll need to add [share] sections to /etc/samba/smb.conf and create Samba users."
else
    log_message "Samba services failed to start. Please check logs: sudo journalctl -xeu smbd; sudo journalctl -xeu nmbd"
    log_message "You may need to manually troubleshoot the issue."
fi

log_message "Script finished."
