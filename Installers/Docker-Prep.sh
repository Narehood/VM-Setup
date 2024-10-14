#!/bin/bash

# Clone the XenOrchestraInstallerUpdater repository
REPO_URL="https://github.com/Narehood/Docker-Prep"
DEST_DIR="Docker-Prep"

if [ -d "$DEST_DIR" ] || [ -f "$DEST_DIR" ]; then
    read -p "$DEST_DIR already exists. Do you want to replace it? (y/n): " REPLACE
    if [ "$REPLACE" != "y" ]; then
        echo "Operation aborted."
        exit 1
    fi
    rm -rf "$DEST_DIR"
fi

git clone "$REPO_URL"
cd "$DEST_DIR"

# Run the installation script
bash install.sh
