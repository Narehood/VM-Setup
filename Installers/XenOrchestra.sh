#!/bin/bash

# Define the directory and repository URL
repo_dir="XenOrchestraInstallerUpdater"
repo_url="https://github.com/Narehood/XenOrchestraInstallerUpdater"

# Check if the directory exists
if [ -d "$repo_dir" ]; then
    # Remove the directory and its contents
    rm -rf "$repo_dir"
fi

# Clone the XenOrchestraInstallerUpdater repository to the home directory of the current user
cd
git clone "$repo_url"
cd "$repo_dir"

# Run the installation script
bash xo-install.sh
