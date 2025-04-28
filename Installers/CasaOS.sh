#!/bin/bash

echo "This script will install CasaOS on your system."
read -p "Do you want to continue? (y/n) " confirm

if [[ "$confirm" != "y" ]]; then
    echo "Installation canceled."
    exit 1
fi

echo "Starting installation..."
curl -fsSL https://get.casaos.io | sudo bash

echo "Installation completed successfully!"
