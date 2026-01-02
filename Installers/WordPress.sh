#!/bin/bash
set -euo pipefail

# REQUIRES_ROOT: true
# DESCRIPTION: Installs WordPress with Apache, MySQL, PHP, and auto-generated SSL certificates

VERSION="2.0.0"
INSTALL_DIR="/var/www/html"
SSL_DIR="/etc/apache2/ssl"
CREDS_FILE="/root/.wp-creds"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_step() {
    echo -e "\n${BLUE}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

cleanup() {
    :
}
trap cleanup EXIT

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script requires root privileges."
        exit 1
    fi
}

detect_os() {
    print_info "Detecting Operating System..."
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS="$ID"
        VERSION_ID="${VERSION_ID:-unknown}"
    else
        print_error "Cannot detect OS"
        exit 1
    fi

    if [[ ! "$OS" =~ ^(debian|ubuntu|pop|linuxmint|kali)$ ]]; then
        print_error "WordPress installer only supports Debian-based systems"
        exit 1
    fi

    print_success "Detected: $OS ($VERSION_ID)"
}

install_pkg() {
    if [[ $# -eq 0 ]]; then
        return 1
    fi
    apt-get install -y -qq "$@" >/dev/null 2>&1
}

update_repos() {
    print_info "Updating package repositories..."
    apt-get update -qq >/dev/null 2>&1
    print_success "Repositories updated."
}

generate_password() {
    openssl rand -base64 32 | tr -d '=' | cut -c1-16
}

validate_domain() {
    local domain="$1"
    [[ "$domain" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]] || [[ "$domain" =~ ^localhost$ ]]
}

show_header() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${CYAN}    WordPress Installation Script${NC}"
    echo -e "${CYAN}           v${VERSION}${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

show_header
check_root
detect_os

print_step "Generating Database Credentials"
DB_NAME="wp_$(date +%s)"
DB_USER="$DB_NAME"
DB_PASSWORD=$(generate_password)
MYSQL_ROOT_PASSWORD=$(generate_password)
print_success "Database credentials generated."

print_step "SSL Certificate Configuration"
read -p "Enter domain name (for SSL certificate) [localhost]: " DOMAIN_NAME
DOMAIN_NAME="${DOMAIN_NAME:-localhost}"

if ! validate_domain "$DOMAIN_NAME"; then
    print_warn "Invalid domain. Using 'localhost'."
    DOMAIN_NAME="localhost"
fi

print_success "Domain set to: $DOMAIN_NAME"

print_step "Installing Required Packages"
update_repos

packages=(
    "apache2"
    "mysql-server"
    "php"
    "php-bz2"
    "php-mysqli"
    "php-curl"
    "php-gd"
    "php-intl"
    "php-common"
    "php-mbstring"
    "php-xml"
    "openssl"
    "curl"
    "wget"
)

for pkg in "${packages[@]}"; do
    if ! install_pkg "$pkg"; then
        print_error "Failed to install $pkg"
        exit 1
    fi
done

print_success "All packages installed."

print_step "Configuring Apache"
if [[ -f /var/www/html/index.html ]]; then
    rm /var/www/html/index.html
fi

systemctl enable apache2 >/dev/null 2>&1
systemctl start apache2 >/dev/null 2>&1
print_success "Apache enabled and started."

a2enmod rewrite >/dev/null 2>&1
a2enmod ssl >/dev/null 2>&1
print_success "Apache modules enabled."

print_step "Configuring MySQL"
systemctl enable mysql >/dev/null 2>&1
systemctl start mysql >/dev/null 2>&1
print_success "MySQL enabled and started."

print_info "Setting MySQL root password..."
/usr/bin/mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';" 2>/dev/null || \
/usr/bin/mysql -e "UPDATE mysql.user SET authentication_string=PASSWORD('$MYSQL_ROOT_PASSWORD') WHERE user='root' AND host='localhost'; FLUSH PRIVILEGES;" 2>/dev/null

cat > /root/.my.cnf << EOF
[client]
user=root
password=$MYSQL_ROOT_PASSWORD
EOF

chmod 600 /root/.my.cnf
print_success "MySQL root password set."

print_info "Enabling htaccess support..."
sed -i '0,/AllowOverride\ None/ s/AllowOverride\ None/AllowOverride\ All/' /etc/apache2/apache2.conf
systemctl restart apache2 >/dev/null 2>&1
print_success "Apache restarted."

print_step "Downloading WordPress"
if [[ -f /tmp/latest.tar.gz ]]; then
    print_info "WordPress package already downloaded."
else
    print_info "Downloading latest WordPress..."
    if ! cd /tmp && wget -q "https://wordpress.org/latest.tar.gz"; then
        print_error "Failed to download WordPress"
        exit 1
    fi
fi
print_success "WordPress downloaded."

print_step "Extracting WordPress"
/bin/tar -C "$INSTALL_DIR" -zxf /tmp/latest.tar.gz --strip-components=1
chown -R www-data:www-data "$INSTALL_DIR"
print_success "WordPress extracted and permissions set."

print_step "Creating Database"
/usr/bin/mysql -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
/usr/bin/mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
/usr/bin/mysql -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';"
/usr/bin/mysql -e "FLUSH PRIVILEGES;"
print_success "Database and user created."

print_step "Configuring WordPress"
cp "$INSTALL_DIR/wp-config-sample.php" "$INSTALL_DIR/wp-config.php"
sed -i "s/database_name_here/$DB_NAME/g" "$INSTALL_DIR/wp-config.php"
sed -i "s/username_here/$DB_USER/g" "$INSTALL_DIR/wp-config.php"
sed -i "s/password_here/$DB_PASSWORD/g" "$INSTALL_DIR/wp-config.php"

cat >> "$INSTALL_DIR/wp-config.php" << 'EOF'
define('FS_METHOD', 'direct');
EOF

print_info "Fetching WordPress salts..."
SALT_OUTPUT=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
if [[ -n "$SALT_OUTPUT" ]]; then
    sed -i '/define(.AUTH_KEY/,/define(.NONCE_SALT/d' "$INSTALL_DIR/wp-config.php"
    echo "$SALT_OUTPUT" >> "$INSTALL_DIR/wp-config.php"
    print_success "WordPress salts configured."
else
    print_warn "Could not fetch salts automatically. Please update manually."
fi

cat > "$INSTALL_DIR/.htaccess" << 'EOF'
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
RewriteRule ^index.php$ – [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
EOF

chown -R www-data:www-data "$INSTALL_DIR"
print_success "WordPress configuration complete."

print_step "Generating Self-Signed SSL Certificate"
mkdir -p "$SSL_DIR"
/usr/bin/openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$SSL_DIR/apache-selfsigned.key" \
    -out "$SSL_DIR/apache-selfsigned.crt" \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=$DOMAIN_NAME" \
    >/dev/null 2>&1
print_success "SSL certificate generated."

print_step "Configuring Apache SSL"
cat > /etc/apache2/sites-available/wordpress-ssl.conf << EOF
<VirtualHost *:443>
    ServerName $DOMAIN_NAME
    ServerAdmin admin@$DOMAIN_NAME
    DocumentRoot $INSTALL_DIR

    SSLEngine on
    SSLCertificateFile $SSL_DIR/apache-selfsigned.crt
    SSLCertificateKeyFile $SSL_DIR/apache-selfsigned.key

    <Directory $INSTALL_DIR>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/wordpress-error.log
    CustomLog \${APACHE_LOG_DIR}/wordpress-access.log combined
</VirtualHost>
EOF

cat > /etc/apache2/sites-available/wordpress-http.conf << EOF
<VirtualHost *:80>
    ServerName $DOMAIN_NAME
    ServerAdmin admin@$DOMAIN_NAME
    DocumentRoot $INSTALL_DIR

    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^(.*)$ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]

    ErrorLog \${APACHE_LOG_DIR}/wordpress-error.log
    CustomLog \${APACHE_LOG_DIR}/wordpress-access.log combined
</VirtualHost>
EOF

a2ensite wordpress-ssl.conf >/dev/null 2>&1
a2ensite wordpress-http.conf >/dev/null 2>&1
a2enmod rewrite >/dev/null 2>&1
systemctl restart apache2 >/dev/null 2>&1
print_success "Apache SSL configured."

print_step "Saving Credentials"
cat > "$CREDS_FILE" << EOF
WordPress Installation Credentials
===================================
Generated: $(date)

Database Name:     $DB_NAME
Database User:     $DB_USER
Database Password: $DB_PASSWORD
MySQL Root Pass:   $MYSQL_ROOT_PASSWORD

Installation Directory: $INSTALL_DIR
SSL Certificate:        $SSL_DIR/apache-selfsigned.crt
SSL Key:                $SSL_DIR/apache-selfsigned.key
Domain Name:            $DOMAIN_NAME

Access WordPress at: https://$DOMAIN_NAME/wp-admin
EOF

chmod 600 "$CREDS_FILE"
print_success "Credentials saved to $CREDS_FILE"

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}  WordPress Installation Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
print_info "Database Name:     $DB_NAME"
print_info "Database User:     $DB_USER"
print_info "Domain:            $DOMAIN_NAME"
print_info "Installation:      $INSTALL_DIR"
print_info "Credentials File:  $CREDS_FILE (mode 600)"
echo ""
print_info "Access WordPress at: https://$DOMAIN_NAME/wp-admin"
echo ""
