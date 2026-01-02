#!/bin/bash
set -euo pipefail

# REQUIRES_ROOT: true
# DESCRIPTION: Installs WordPress with Apache, MariaDB/MySQL, PHP, and SSL certificates

VERSION="2.3.3"
INSTALL_DIR="/var/www/html"
CREDS_FILE="/root/.wp-creds"
LOG_FILE="/var/log/wordpress-install.log"

INSTALLATION_FAILED=1

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
WEB_SERVICE=""
WEB_USER=""
SSL_DIR=""
DB_USER=""
DB_NAME=""
DB_SERVICE=""
PHP_VERSION=""
VHOST_FILES=()
PACKAGES_INSTALLED=()

# print_step prints a step message prefixed with `[STEP]` (blue) and appends it to the log file.
print_step() {
    echo -e "\n${BLUE}[STEP]${NC} $1" | tee -a "$LOG_FILE"
}

# print_success prints a success message prefixed with a green [OK] tag, echoes it to stdout and appends the same line to the log file.
print_success() {
    echo -e "${GREEN}[OK]${NC} $1" | tee -a "$LOG_FILE"
}

# print_warn prints a warning message prefixed with "[WARN]" in yellow, echoes it to stdout, and appends it to the log file.
print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"
}

# print_error prints an error message prefixed with `[ERROR]` in red and appends it to the configured log file.
print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# print_info prints an informational message prefixed with "[INFO]" and appends it to the log file.
print_info() {
    echo -e "${CYAN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

# show_header clears the terminal and prints the script header banner including the script version.
show_header() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${CYAN}    WordPress Installation Script${NC}"
    echo -e "${CYAN}           v${VERSION}${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

# cleanup rolls back a failed installation when INSTALLATION_FAILED is non-zero by stopping services, removing WordPress files and vhost configs, dropping the created database and user, and deleting temporary files and credentials.
cleanup() {
    if [[ $INSTALLATION_FAILED -ne 0 ]]; then
        print_error "Installation failed. Rolling back changes..." >&2
        
        print_info "Stopping services..." >&2
        if [[ -n "$WEB_SERVICE" ]]; then
            systemctl stop "$WEB_SERVICE" 2>/dev/null || true
            systemctl disable "$WEB_SERVICE" 2>/dev/null || true
        fi
        if [[ -n "$DB_SERVICE" ]]; then
            systemctl stop "$DB_SERVICE" 2>/dev/null || true
        fi
        
        print_info "Removing WordPress files..." >&2
        rm -rf "${INSTALL_DIR:?}"/wordpress 2>/dev/null || true
        rm -f "${INSTALL_DIR:?}"/wp-config.php 2>/dev/null || true
        rm -f "${INSTALL_DIR:?}"/.htaccess 2>/dev/null || true
        
        print_info "Removing virtual host configurations..." >&2
        for vhost in "${VHOST_FILES[@]}"; do
            rm -f "$vhost" 2>/dev/null || true
        done
        
        if [[ -n "$DB_NAME" ]] && [[ -n "$DB_USER" ]]; then
            print_info "Dropping database and user..." >&2
            /usr/bin/mysql -e "DROP DATABASE IF EXISTS \`$DB_NAME\`;" 2>/dev/null || true
            /usr/bin/mysql -e "DROP USER IF EXISTS '$DB_USER'@'localhost';" 2>/dev/null || true
        fi
        
        print_info "Removing temporary files..." >&2
        rm -f /tmp/latest.tar.gz 2>/dev/null || true
        rm -f "$CREDS_FILE" 2>/dev/null || true
        
        print_error "Rollback complete. Check $LOG_FILE for details." >&2
    fi
}

trap cleanup EXIT

# check_root ensures the script is executed as the root user and exits with status 1 (after printing an error) if not.
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script requires root privileges."
        exit 1
    fi
}

# check_existing_wordpress checks for an existing WordPress installation at INSTALL_DIR and exits with status 1 after printing an error if wp-config.php is present.
check_existing_wordpress() {
    if [[ -f "$INSTALL_DIR/wp-config.php" ]]; then
        print_error "WordPress appears to already be installed at $INSTALL_DIR"
        print_error "Please back up your site and remove existing files before reinstalling."
        exit 1
    fi
}

# detect_os detects the operating system, sets the global variables `OS` and `VERSION_ID` from /etc/os-release or fallback files, and logs the detected values.
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

# is_debian_based determines whether the detected OS is a Debian-based distribution (debian, ubuntu, pop, linuxmint, kali).
# Returns 0 if `$OS` matches a Debian-based ID, non-zero otherwise.
is_debian_based() {
    [[ "$OS" =~ ^(debian|ubuntu|pop|linuxmint|kali)$ ]]
}

# is_rhel_based indicates whether the detected OS is a RHEL-family distribution (fedora, redhat, centos, rocky, almalinux).
is_rhel_based() {
    [[ "$OS" =~ ^(fedora|redhat|centos|rocky|almalinux)$ ]]
}

# is_arch_based returns true if $OS identifies an Arch Linux family (arch, endeavouros, or manjaro).
is_arch_based() {
    [[ "$OS" =~ ^(arch|endeavouros|manjaro)$ ]]
}

# is_suse_based determines if the detected OS is SUSE, openSUSE, or SLES.
is_suse_based() {
    [[ "$OS" =~ ^(suse|opensuse.*|sles)$ ]]
}

# update_repos updates package repositories for the detected OS and sets PKG_MANAGER_UPDATED="true"; returns a non-zero status if the OS is not supported.
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

# install_pkg installs one or more packages using the detected OS package manager and appends successfully installed package names to PACKAGES_INSTALLED.
# Returns 0 on success for all requested packages, non-zero if installation fails or no packages were provided.
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

    if [[ $result -eq 0 ]]; then
        for pkg in "$@"; do
            PACKAGES_INSTALLED+=("$pkg")
        done
    fi

    return $result
}

# get_available_php_versions prints candidate PHP versions for the current system, one per line.
# It detects the OS family and queries the package system when possible (Debian/RHEL/Arch), falling back to a sensible default list if detection fails.
get_available_php_versions() {
    local versions=()
    
    if is_debian_based; then
        versions+=($(apt-cache search --names-only '^php[0-9]+$' 2>/dev/null | awk '{print $1}' | sed 's/php//' | sort -V | tail -5))
    elif is_rhel_based; then
        versions+=($(dnf module list php 2>/dev/null | grep -E '^\s+php' | awk '{print $1}' | sed 's/php://' | sort -V | tail -5))
    elif is_arch_based; then
        if pacman -Qs php &>/dev/null; then
            versions+=("$(pacman -Q php 2>/dev/null | awk '{print $2}' | cut -d- -f1)")
        else
            versions+=("8.3" "8.2" "8.1")
        fi
    fi
    
    if [[ ${#versions[@]} -eq 0 ]]; then
        versions=("8.3" "8.2" "8.1" "8.0" "7.4")
    fi
    
    printf '%s\n' "${versions[@]}"
}

# get_active_php_version prints the active PHP version (major.minor) to stdout; prints "none" if PHP is not installed, or "unknown" if PHP is installed but the version cannot be determined.
get_active_php_version() {
    if command -v php &>/dev/null; then
        php -v 2>/dev/null | head -n1 | grep -oP 'PHP\s+\K[0-9]+\.[0-9]+' || echo "unknown"
    else
        echo "none"
    fi
}

# select_php_version selects a PHP version from available candidates, prompts the user when running interactively (defaults to the first option in non-interactive mode), validates the choice, and sets the global `PHP_VERSION` variable.
select_php_version() {
    print_step "PHP Version Selection"
    
    local active_version
    active_version=$(get_active_php_version)
    print_info "Currently active PHP version: $active_version"
    echo ""
    
    local available_versions
    available_versions=$(get_available_php_versions)
    local versions_array=()
    
    echo -e "${CYAN}Available PHP Versions:${NC}"
    local i=1
    while IFS= read -r version; do
        versions_array+=("$version")
        local marker=""
        if [[ "$version" == "$active_version" ]]; then
            marker=" (active)"
        fi
        printf "  ${BLUE}%d.${NC} PHP %s%s\n" "$i" "$version" "$marker"
        ((i++))
    done <<< "$available_versions"
    
    echo ""
    
    if [[ -t 0 ]]; then
        read -p "  Select PHP version [1-${#versions_array[@]}]: " php_selection
    else
        php_selection="1"
        print_info "Non-interactive mode: using default PHP version"
    fi
    
    if ! [[ "$php_selection" =~ ^[0-9]+$ ]] || [[ $php_selection -lt 1 ]] || [[ $php_selection -gt ${#versions_array[@]} ]]; then
        print_error "Invalid selection"
        exit 1
    fi
    
    PHP_VERSION="${versions_array[$((php_selection - 1))]}"
    print_success "Selected PHP version: $PHP_VERSION"
}

# validate_domain validates that the given domain is a fully qualified domain name (FQDN) or `localhost`.
validate_domain() {
    local domain="$1"
    [[ "$domain" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]] || [[ "$domain" =~ ^localhost$ ]]
}

# generate_password generates a 16-character random password using OpenSSL's base64 RNG.
generate_password() {
    openssl rand -base64 32 | tr -d '=' | cut -c1-16
}

# get_database_version gets the installed MySQL/MariaDB server version string or echoes "unknown" if it cannot be determined.
get_database_version() {
    /usr/bin/mysql -N -B -e "SELECT VERSION();" 2>/dev/null | head -n1 || echo "unknown"
}

# set_database_root_password sets the MariaDB/MySQL root account password to the provided value, choosing the appropriate SQL syntax (ALTER USER or legacy SET PASSWORD) based on the detected database version.
set_database_root_password() {
    local password="$1"
    local db_version
    
    db_version=$(get_database_version)
    
    print_info "Detected database version: $db_version"
    
    if [[ "$db_version" == "unknown" ]]; then
        print_warn "Could not detect database version, attempting ALTER USER"
        /usr/bin/mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$password';" 2>/dev/null && return 0
        print_warn "ALTER USER failed, trying legacy method with PASSWORD()"
        /usr/bin/mysql -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$password');" 2>/dev/null && return 0
        return 1
    fi
    
    if [[ "$db_version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
        local major="${BASH_REMATCH[1]}"
        local minor="${BASH_REMATCH[2]}"
        local patch="${BASH_REMATCH[3]}"
        
        if [[ "$db_version" =~ -MariaDB ]]; then
            print_info "Detected MariaDB - using ALTER USER syntax"
            /usr/bin/mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$password';" 2>/dev/null || return 1
            return 0
        fi
        
        if [[ $major -gt 8 ]]; then
            print_info "MySQL $major.$minor.$patch detected - using ALTER USER"
            /usr/bin/mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$password';" 2>/dev/null || return 1
        elif [[ $major -eq 8 ]]; then
            print_info "MySQL 8.0.x detected - using ALTER USER"
            /usr/bin/mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$password';" 2>/dev/null || return 1
        elif [[ $major -eq 5 && $minor -ge 7 ]] || [[ $major -gt 5 ]]; then
            print_info "MySQL $major.$minor.$patch detected - using ALTER USER"
            /usr/bin/mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$password';" 2>/dev/null || return 1
        else
            print_warn "MySQL $major.$minor.$patch (pre-5.7.6) detected - using legacy SET PASSWORD with PASSWORD()"
            /usr/bin/mysql -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$password');" 2>/dev/null || return 1
        fi
    else
        print_info "Could not parse version format, attempting ALTER USER"
        /usr/bin/mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$password';" 2>/dev/null || return 1
    fi
    
    return 0
}

# get_php_packages generates newline-separated package names required for PHP on the detected OS, using `version` to build distribution-specific package names (e.g. `8.1` -> `php8.1` on Debian).
get_php_packages() {
    local version="$1"
    local packages=()
    
    if is_debian_based; then
        packages=(
            "php${version}"
            "php${version}-bz2"
            "php${version}-mysqli"
            "php${version}-curl"
            "php${version}-gd"
            "php${version}-intl"
            "php${version}-common"
            "php${version}-mbstring"
            "php${version}-xml"
        )
    elif is_rhel_based; then
        packages=(
            "php"
            "php-bz2"
            "php-mysqli"
            "php-curl"
            "php-gd"
            "php-intl"
            "php-common"
            "php-mbstring"
            "php-xml"
        )
    elif is_arch_based; then
        packages=(
            "php"
            "php-gd"
            "php-curl"
            "php-intl"
        )
    fi
    
    printf '%s\n' "${packages[@]}"
}

# enable_php_apache enables the Apache PHP module matching $PHP_VERSION and ensures the prefork MPM is active on Debian-based systems.
# On non-Debian systems this function is a no-op.
enable_php_apache() {
    if is_debian_based; then
        a2enmod "php${PHP_VERSION}" >/dev/null 2>&1 || true
        a2dismod mpm_prefork >/dev/null 2>&1 || true
        a2enmod mpm_prefork >/dev/null 2>&1 || true
    fi
}

# configure_ssl_dir sets the SSL_DIR variable to the appropriate SSL certificate directory for the detected OS family and logs the chosen path.
configure_ssl_dir() {
    if is_debian_based; then
        SSL_DIR="/etc/apache2/ssl"
    elif is_rhel_based || is_arch_based; then
        SSL_DIR="/etc/httpd/ssl"
    else
        SSL_DIR="/etc/ssl/wordpress"
    fi
    
    print_info "SSL directory: $SSL_DIR"
}

# select_domain determines the domain to use for the SSL certificate and sets the global DOMAIN_NAME variable, preferring the DOMAIN_NAME environment variable, prompting the user in interactive mode, or defaulting to "localhost"; it validates the chosen domain and falls back to "localhost" with a warning if invalid.
select_domain() {
    print_step "Domain Configuration"
    
    local domain_input=""
    
    if [[ -n "${DOMAIN_NAME:-}" ]]; then
        print_info "Using DOMAIN_NAME environment variable: $DOMAIN_NAME"
        domain_input="$DOMAIN_NAME"
    elif [[ -t 0 ]]; then
        read -p "Enter domain name (for SSL certificate) [localhost]: " domain_input
        domain_input="${domain_input:-localhost}"
    else
        print_info "Non-interactive mode: using default domain 'localhost'"
        domain_input="localhost"
    fi
    
    if ! validate_domain "$domain_input"; then
        print_warn "Invalid domain '$domain_input'. Using 'localhost'."
        domain_input="localhost"
    fi
    
    DOMAIN_NAME="$domain_input"
    print_success "Domain set to: $DOMAIN_NAME"
}

show_header
print_info "Initializing log: $LOG_FILE"

check_root
detect_os
check_existing_wordpress

if ! is_debian_based && ! is_rhel_based && ! is_arch_based; then
    print_error "WordPress installer supports Debian, RHEL, and Arch-based systems only"
    exit 1
fi

print_step "Generating Database Credentials"
DB_NAME="wp_$(date +%s)"
DB_USER="$DB_NAME"
DB_PASSWORD=$(generate_password)
DB_ROOT_PASSWORD=$(generate_password)
print_success "Database credentials generated."

select_php_version
select_domain

print_step "Installing Required Packages"
update_repos

if is_debian_based; then
    base_packages=(
        "apache2"
        "mariadb-server"
        "openssl"
        "curl"
        "wget"
    )
elif is_rhel_based; then
    base_packages=(
        "httpd"
        "mariadb-server"
        "openssl"
        "curl"
        "wget"
    )
    dnf install -y epel-release -q >/dev/null 2>&1 || true
elif is_arch_based; then
    base_packages=(
        "apache"
        "mariadb"
        "openssl"
        "curl"
        "wget"
    )
fi

for pkg in "${base_packages[@]}"; do
    if ! install_pkg "$pkg"; then
        print_error "Failed to install $pkg"
        exit 1
    fi
done

print_info "Installing PHP $PHP_VERSION and extensions..."
php_packages=($(get_php_packages "$PHP_VERSION"))

for pkg in "${php_packages[@]}"; do
    if ! install_pkg "$pkg"; then
        print_warn "Could not install $pkg, continuing..."
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

configure_ssl_dir

if [[ -f /var/www/html/index.html ]]; then
    rm /var/www/html/index.html
fi

systemctl enable "$WEB_SERVICE" >/dev/null 2>&1
systemctl start "$WEB_SERVICE" >/dev/null 2>&1
print_success "Web server enabled and started."

if is_debian_based; then
    a2enmod rewrite >/dev/null 2>&1
    a2enmod ssl >/dev/null 2>&1
    enable_php_apache
elif is_rhel_based || is_arch_based; then
    sed -i 's/^#LoadModule rewrite_module/LoadModule rewrite_module/' "$APACHE_CONF" 2>/dev/null || true
    sed -i 's/^#LoadModule ssl_module/LoadModule ssl_module/' "$APACHE_CONF" 2>/dev/null || true
    sed -i 's/^#LoadModule proxy_fcgi_module/LoadModule proxy_fcgi_module/' "$APACHE_CONF" 2>/dev/null || true
fi

print_success "Web server modules enabled."

print_step "Configuring Database"

DB_SERVICE="mariadb"
if ! systemctl enable "$DB_SERVICE" >/dev/null 2>&1; then
    DB_SERVICE="mysql"
    systemctl enable "$DB_SERVICE" >/dev/null 2>&1 || true
fi

systemctl start "$DB_SERVICE" >/dev/null 2>&1
print_success "Database service ($DB_SERVICE) started."

print_info "Setting database root password..."

if ! set_database_root_password "$DB_ROOT_PASSWORD"; then
    print_error "Failed to set database root password"
    exit 1
fi

cat > /root/.my.cnf << EOF
[client]
user=root
password=$DB_ROOT_PASSWORD
EOF

chmod 600 /root/.my.cnf
print_success "Database root password set."

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

if [[ -f "$INSTALL_DIR/index.php" ]] || [[ -f "$INSTALL_DIR/wp-load.php" ]]; then
    print_error "WordPress files already exist in $INSTALL_DIR"
    print_error "Please remove existing files before proceeding"
    exit 1
fi

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
    if grep -q "^?>" "$INSTALL_DIR/wp-config.php"; then
        sed -i '/^?>$/d' "$INSTALL_DIR/wp-config.php"
        echo "$SALT_OUTPUT" >> "$INSTALL_DIR/wp-config.php"
        echo "?>" >> "$INSTALL_DIR/wp-config.php"
    else
        sed -i '/define(.AUTH_KEY/,/define(.NONCE_SALT/d' "$INSTALL_DIR/wp-config.php"
        echo "$SALT_OUTPUT" >> "$INSTALL_DIR/wp-config.php"
    fi
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
chmod 600 "$SSL_DIR/apache-selfsigned.key"
print_success "SSL certificate generated."

print_step "Configuring SSL Virtual Hosts"

if is_debian_based; then
    WORDPRESS_SSL_VHOST="$SITES_AVAILABLE/wordpress-ssl.conf"
    WORDPRESS_HTTP_VHOST="$SITES_AVAILABLE/wordpress-http.conf"
    
    cat > "$WORDPRESS_SSL_VHOST" << EOF
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

    cat > "$WORDPRESS_HTTP_VHOST" << EOF
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

    VHOST_FILES+=("$WORDPRESS_SSL_VHOST" "$WORDPRESS_HTTP_VHOST")
    a2ensite wordpress-ssl.conf >/dev/null 2>&1
    a2ensite wordpress-http.conf >/dev/null 2>&1

else
    WORDPRESS_VHOST="$SITES_AVAILABLE/wordpress.conf"
    
    cat > "$WORDPRESS_VHOST" << EOF
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

    VHOST_FILES+=("$WORDPRESS_VHOST")
fi

a2enmod rewrite >/dev/null 2>&1 || true
systemctl restart "$WEB_SERVICE" >/dev/null 2>&1
print_success "SSL and virtual hosts configured."

print_step "Saving Credentials"

cat > "$CREDS_FILE" << EOF
WordPress Installation Credentials
===================================
Generated: $(date)
OS: $OS
PHP Version: $PHP_VERSION
Database: MariaDB

Database Name:     $DB_NAME
Database User:     $DB_USER
Database Password: $DB_PASSWORD
Database Root Pass: $DB_ROOT_PASSWORD

Installation Directory: $INSTALL_DIR
SSL Certificate:        $SSL_DIR/apache-selfsigned.crt
SSL Key:                $SSL_DIR/apache-selfsigned.key
Domain Name:            $DOMAIN_NAME
Web Server:             $WEB_SERVICE
Web Server User:        $WEB_USER
Database Service:       $DB_SERVICE

Access WordPress at: https://$DOMAIN_NAME/wp-admin

SECURITY WARNING:
=================
This file contains sensitive credentials. Please:

1. Securely store this information in a password manager
2. Delete this file after recording the credentials
3. Exclude backups of this file from your backup strategy
4. Ensure any backups containing these credentials are encrypted
5. Immediately rotate all credentials if this file is exposed

Do NOT share this file with others.
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
print_info "Database Service:  $DB_SERVICE"
print_info "PHP Version:       $PHP_VERSION"
print_info "Domain:            $DOMAIN_NAME"
print_info "Installation:      $INSTALL_DIR"
print_info "Credentials File:  $CREDS_FILE (mode 600)"
print_info "Log File:          $LOG_FILE"
echo ""
print_warn "⚠ Review security warning in $CREDS_FILE"
echo ""
print_info "Access WordPress at: https://$DOMAIN_NAME/wp-admin"
echo ""

INSTALLATION_FAILED=0