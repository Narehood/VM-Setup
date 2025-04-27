#!/bin/bash

# Installer Credit: Pterodactyl Installer Repository
# https://github.com/pterodactyl-installer/pterodactyl-installer

DOMAIN="pterodactyl-installer.se"
EXPECTED_DATE="2020-10-23"

# Ensure the script is running as root
if [[ "$(whoami)" != "root" ]]; then
    echo "Error: This script must be run as root!"
    exit 1
fi

# Check domain registration date using whois
REG_DATE=$(whois "$DOMAIN" | grep -i "created" | awk '{print $NF}')
if [[ -z "$REG_DATE" ]]; then
    echo "Error: Unable to fetch domain registration date."
    exit 1
fi

# Verify registration date
if [[ "$REG_DATE" != "$EXPECTED_DATE" ]]; then
    echo "Warning: The domain ($DOMAIN) does not match the expected registration date ($EXPECTED_DATE). Potential risk!"
    exit 1
fi

# Verify SSL certificate validity
if ! curl --silent --fail --head "https://$DOMAIN" | grep -q "HTTP/2 200"; then
    echo "Error: Invalid SSL certificate or site unreachable."
    exit 1
fi

# Proceed with installation
bash <(curl -s https://$DOMAIN)
