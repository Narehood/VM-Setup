#!/bin/bash

# --- CONFIGURATION ---
REPO_DIR="XenOrchestraInstallerUpdater"
REPO_URL="https://github.com/Narehood/XenOrchestraInstallerUpdater"

# Ensure we are in the home directory (or wherever you want this installed)
cd "$HOME" || { echo "Failed to change to home directory"; exit 1; }

# --- UPDATE LOGIC ---

if [ -d "$REPO_DIR" ]; then
    echo "Directory $REPO_DIR found. Checking for updates..."
    cd "$REPO_DIR" || exit 1

    # Verify it is a valid git repo
    if [ -d ".git" ]; then
        # Fetch latest info without merging
        git remote update > /dev/null 2>&1
        
        LOCAL=$(git rev-parse @)
        REMOTE=$(git rev-parse @{u})

        if [ "$LOCAL" = "$REMOTE" ]; then
            echo "Xen Orchestra Installer is already up to date."
        else
            echo "Update available. Pulling latest changes..."
            git pull
        fi
    else
        echo "Warning: Directory exists but is not a valid git repository."
        read -p "Delete and re-clone? (y/n): " REPLACE
        if [ "$REPLACE" == "y" ]; then
            cd ..
            rm -rf "$REPO_DIR"
            echo "Cloning repository..."
            git clone "$REPO_URL"
            cd "$REPO_DIR" || exit 1
        else
            echo "Using existing directory as-is."
        fi
    fi
else
    echo "Cloning Xen Orchestra Installer..."
    git clone "$REPO_URL"
    cd "$REPO_DIR" || exit 1
fi

# --- EXECUTION ---
echo "Starting installation script..."
if [ -f "xo-install.sh" ]; then
    bash xo-install.sh
else
    echo "Error: xo-install.sh not found in $REPO_DIR"
    exit 1
fi
