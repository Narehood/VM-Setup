#!/bin/bash

# Get the server's IP address
SERVER_IP=$(hostname -I | awk '{print $1}')

# Update package list
echo "Updating package list..."
sudo apt update

# Install Apache
echo "Installing Apache..."
sudo apt install -y apache2

# Install MySQL
echo "Installing MySQL..."
sudo apt install -y mysql-server

# Secure MySQL
echo "Securing MySQL installation..."
sudo mysql_secure_installation

# Install PHP
echo "Installing PHP..."
sudo apt install -y php libapache2-mod-php php-mysql

# Restart Apache
echo "Restarting Apache..."
sudo systemctl restart apache2

# Open HTTP (port 80) and HTTPS (port 443) ports
echo "Configuring firewall to allow HTTP and HTTPS traffic..."
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw reload

# Print completion message
echo "LAMP stack installation complete! You can check PHP info at http://$SERVER_IP"
