#!/bin/bash

REPO_URL="https://github.com/Narehood/Docker-Prep"
DEST_DIR="Docker-Prep"

# Function to handle the update logic
update_repo() {
    echo "Checking for updates..."
    # Fetch latest metadata without merging yet
    git remote update > /dev/null 2>&1
    
    LOCAL=$(git rev-parse @)
    REMOTE=$(git rev-parse @{u})

    if [ "$LOCAL" = "$REMOTE" ]; then
        echo "Files are up to date."
    else
        echo "Update available. Pulling latest changes..."
        git pull
    fi
}

# Main Logic
if [ -d "$DEST_DIR" ]; then
    cd "$DEST_DIR" || exit 1
    
    # Verify it is actually a git repo before trying to update
    if [ -d ".git" ]; then
        update_repo
    else
        # Fallback if folder exists but isn't a git repo (e.g. manual copy)
        echo "Directory exists but is not a linked git repository."
        read -p "Delete and re-clone? (y/n): " REPLACE
        if [ "$REPLACE" == "y" ]; then
            cd ..
            rm -rf "$DEST_DIR"
            git clone "$REPO_URL"
            cd "$DEST_DIR" || exit 1
        else
            echo "Operation aborted."
            exit 1
        fi
    fi
else
    # Fresh install
    echo "Cloning repository..."
    git clone "$REPO_URL"
    cd "$DEST_DIR" || exit 1
fi

# Run the installation script
echo "Executing install script..."
bash install.sh
