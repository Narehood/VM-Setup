#!/bin/bash
set -euo pipefail

# REQUIRES_ROOT: true
# DESCRIPTION: Installs WordPress with Apache, MySQL/MariaDB, PHP, and SSL certificates

VERSION="2.1.0"
INSTALL_DIR="/var/www/html"
SSL_DIR="/etc/apache2/ssl"
CREDS_FILE="/root/.wp-creds"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
NC='\033[0m'

export PATH=$PATH:/usr/local/sbin:/usr/sbin:/sbin

PKG_MANAGER_UPDATED="false"
OS=""
VERSION_ID=""

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

show_header() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${CYAN}    WordPress Installation Script${NC}"
    echo -e "${CYAN}           v${VERSION}${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
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
    elif [[ -f /etc/redhat-release ]]; then
        OS="redhat"
        VERSION_ID="unknown"
    elif [[ -f /etc/debian_version ]]; then
        OS="debian"
        VERSION_ID="unknown"
    else
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
        VERSION_ID="unknown"
    fi
    print_success "Detected: $OS ($VERSION_ID)"
}

is_debian_based() {
    [[ "$OS" =~ ^(debian|ubuntu|pop|linuxmint|kali)$ ]]
}

is_rhel_based() {
    [[ "$OS" =~ ^(fedora|redhat|centos|rocky|almalinux)$ ]]
}

is_arch_based() {
    [[ "$OS" =~ ^(arch|endeavouros|manjaro)$ ]]
}

is_suse_based() {
    [[ "$OS" =~ ^(suse|opensuse.*|sles)$ ]]
}

update_repos() {
    if [[ "$PKG_MANAGER_UPDATED" == "true" ]]; then
        return
    fi

    print_info "Updating package repositories..."

    if [[ "$OS" == "alpine" ]]; then
        apk update >/dev/null 2>&1
    elif is_debian_based; then
        apt-get update -qq >/dev/null 2>&1
    elif is_rhel_based; then
        dnf makecache -q >/dev/null 2>&1
    elif is_arch_based; then
        pacman -Sy --noconfirm >/dev/null 2>&1
    elif is_suse_based; then
        zypper refresh -q >/dev/null 2>&1
    else
        print_warn "Unknown OS for repo update"
        return 1
    fi

    PKG_MANAGER_UPDATED="true"
    print_success "Repositories updated."
}

install_pkg() {
    if [[ $# -eq 0 ]]; then
        return 1
    fi

    local result=0

    if [[ "$OS" == "alpine" ]]; then
        apk add --quiet "$@" >/dev/null 2>&1 || result=$?
    elif is_arch_based; then
        pacman -S --noconfirm --needed "$@" >/dev/null 2>&1 || result=$?
    elif is_debian_based; then
        apt-get install -y -qq "$@" >/dev/null 2>&1 || result=$?
    elif is_rhel_based; then
        dnf install -y -q "$@" >/dev/null 2>&1 || result=$?
    elif is_suse_based; then
        zypper install -y -q "$@" >/dev/null 2>&1 || result=$?
    else
        print_warn "Unsupported OS for package install"
        return 1
    fi

    return $result
}

validate_domain() {
    local domain="$1"
    [[ "$domain" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]] || [[ "$domain" =~ ^localhost$ ]]
}

generate_password() {
    openssl rand -base64 32 | tr -d '=' | cut -c1-16
}

show_header
check_root
detect_os

if ! is_debian_based && ! is_rhel_based && ! is_arch_based; then
    print_error "WordPress installer supports Debian, RHEL, and Arch-based systems only"
    exit 1
fi

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

if is_debian_based; then
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
elif is_rhel_based; then
    packages=(
        "httpd"
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
    dnf install -y epel-release -q >/dev/null 2>&1 || true
elif is_arch_based; then
    packages=(
        "apache"
        "mysql"
        "php"
        "php-bz2"
        "php-gd"
        "php-curl"
        "php-intl"
        "php-mbstring"
        "openssl"
        "curl"
        "wget"
    )
fi

for pkg in "${packages[@]}"; do
    if ! install_pkg "$pkg"; then
        print_error "Failed to install $pkg"
        exit 1
    fi
done

print_success "All packages installed."

print_step "Configuring Web Server"

if is_debian_based; then
    WEB_SERVICE="apache2"
    WEB_USER="www-data"
    APACHE_CONF="/etc/apache2/apache2.conf"
    SITES_AVAILABLE="/etc/apache2/sites-available"
elif is_rhel_based; then
    WEB_SERVICE="httpd"
    WEB_USER="apache"
    APACHE_CONF="/etc/httpd/conf/httpd.conf"
    SITES_AVAILABLE="/etc/httpd/conf.d"
    mkdir -p "$SITES_AVAILABLE"
elif is_arch_based; then
    WEB_SERVICE="httpd"
    WEB_USER="http"
    APACHE_CONF="/etc/httpd/conf/httpd.conf"
    SITES_AVAILABLE="/etc/httpd/conf.d"
    mkdir -p "$SITES_AVAILABLE"
fi

if [[ -f /var/www/html/index.html ]]; then
    rm /var/www/html/index.html
fi

systemctl enable "$WEB_SERVICE" >/dev/null 2>&1
systemctl start "$WEB_SERVICE" >/dev/null 2>&1
print_success "Web server enabled and started."

if is_debian_based; then
    a2enmod rewrite >/dev/null 2>&1
    a2enmod ssl >/dev/null 2>&1
elif is_rhel_based || is_arch_based; then
    sed -i 's/^#LoadModule rewrite_module/LoadModule rewrite_module/' "$APACHE_CONF"
    sed -i 's/^#LoadModule ssl_module/LoadModule ssl_module/' "$APACHE_CONF"
fi

print_success "Web server modules enabled."

print_step "Configuring Database"

systemctl enable mysql >/dev/null 2>&1 || systemctl enable mariadb >/dev/null 2>&1
systemctl start mysql >/dev/null 2>&1 || systemctl start mariadb >/dev/null 2>&1
print_success "Database service started."

print_info "Setting database root password..."

/usr/bin/mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';" 2>/dev/null || \
/usr/bin/mysql -e "UPDATE mysql.user SET authentication_string=PASSWORD('$MYSQL_ROOT_PASSWORD') WHERE user='root' AND host='localhost'; FLUSH PRIVILEGES;" 2>/dev/null || \
/usr/bin/mysql -e "SET PASSWORD FOR 'root'@'localhost' = '$MYSQL_ROOT_PASSWORD';" 2>/dev/null

cat > /root/.my.cnf << EOF
[client]
user=root
password=$MYSQL_ROOT_PASSWORD
EOF

chmod 600 /root/.my.cnf
print_success "Database root password set."

if is_debian_based; then
    print_info "Enabling htaccess support..."
    sed -i '0,/AllowOverride\ None/ s/AllowOverride\ None/AllowOverride\ All/' "$APACHE_CONF"
fi

systemctl restart "$WEB_SERVICE" >/dev/null 2>&1
print_success "Web server configured and restarted."

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
chown -R "$WEB_USER:$WEB_USER" "$INSTALL_DIR"
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

chown -R "$WEB_USER:$WEB_USER" "$INSTALL_DIR"
print_success "WordPress configuration complete."

print_step "Generating Self-Signed SSL Certificate"

mkdir -p "$SSL_DIR"
/usr/bin/openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$SSL_DIR/apache-selfsigned.key" \
    -out "$SSL_DIR/apache-selfsigned.crt" \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=$DOMAIN_NAME" \
    >/dev/null 2>&1
print_success "SSL certificate generated."

print_step "Configuring SSL Virtual Hosts"

if is_debian_based; then
    cat > "$SITES_AVAILABLE/wordpress-ssl.conf" << EOF
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

    cat > "$SITES_AVAILABLE/wordpress-http.conf" << EOF
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

else
    cat > "$SITES_AVAILABLE/wordpress.conf" << EOF
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

    ErrorLog logs/wordpress-error.log
    CustomLog logs/wordpress-access.log combined
</VirtualHost>

<VirtualHost *:80>
    ServerName $DOMAIN_NAME
    ServerAdmin admin@$DOMAIN_NAME
    DocumentRoot $INSTALL_DIR

    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^(.*)$ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]

    ErrorLog logs/wordpress-error.log
    CustomLog logs/wordpress-access.log combined
</VirtualHost>
EOF

fi

a2enmod rewrite >/dev/null 2>&1
systemctl restart "$WEB_SERVICE" >/dev/null 2>&1
print_success "SSL and virtual hosts configured."

print_step "Saving Credentials"

cat > "$CREDS_FILE" << EOF
WordPress Installation Credentials
===================================
Generated: $(date)
OS: $OS

Database Name:     $DB_NAME
Database User:     $DB_USER
Database Password: $DB_PASSWORD
MySQL Root Pass:   $MYSQL_ROOT_PASSWORD

Installation Directory: $INSTALL_DIR
SSL Certificate:        $SSL_DIR/apache-selfsigned.crt
SSL Key:                $SSL_DIR/apache-selfsigned.key
Domain Name:            $DOMAIN_NAME
Web Server:             $WEB_SERVICE
Web Server User:        $WEB_USER

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
