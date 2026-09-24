#!/usr/bin/env bash
# REQUIRES_ROOT: true
# DESCRIPTION: Installs a new WordPress site with Apache, MariaDB, PHP and self-signed TLS
set -Eeuo pipefail

VERSION="3.0.0"
INSTALL_DIR="/var/www/wordpress"
CREDS_FILE="/root/.wp-creds"
WORK_DIR=""
INSTALLATION_FAILED=1
SITE_CREATED=false
DB_CREATED=false
DB_USER_CREATED=false
CREDS_CREATED=false
SSL_CREATED=false
SELINUX_RULE_CREATED=false
DB_NAME="" DB_USER="" SSL_DIR="" WEB_SERVICE=""
VHOST_FILES=()
BACKUP_FILES=()
OS=""

print_info() { printf '[INFO] %s\n' "$*"; }
print_error() { printf '[ERROR] %s\n' "$*" >&2; }
is_debian_based() { [[ "$OS" =~ ^(debian|ubuntu|pop|linuxmint|kali)$ ]]; }
is_rhel_based() { [[ "$OS" =~ ^(fedora|rhel|redhat|centos|rocky|almalinux)$ ]]; }
is_arch_based() { [[ "$OS" =~ ^(arch|endeavouros|manjaro)$ ]]; }
is_suse_based() { [[ "$OS" =~ ^(suse|opensuse.*|sles)$ ]]; }

run_mysql_sql() { mariadb <<< "$1"; }

# Only resources successfully created by this run are eligible for cleanup.
# Packages, existing database accounts and existing services are never removed.
cleanup() {
    local file index
    if ((INSTALLATION_FAILED)); then
        $DB_USER_CREATED && { run_mysql_sql "DROP USER '$DB_USER'@'localhost';" || true; }
        $DB_CREATED && { run_mysql_sql "DROP DATABASE \`$DB_NAME\`;" || true; }
        for file in "${VHOST_FILES[@]}"; do rm -f -- "$file"; done
        for ((index=${#BACKUP_FILES[@]}-1; index>=0; index--)); do
            file=${BACKUP_FILES[$index]}
            cp -p -- "$WORK_DIR/backup-$index" "$file" || true
        done
        $SITE_CREATED && rm -rf -- "${INSTALL_DIR:?}"
        $SSL_CREATED && rm -rf -- "${SSL_DIR:?}"
        $CREDS_CREATED && rm -f -- "$CREDS_FILE"
        $SELINUX_RULE_CREATED && { semanage fcontext -d "$INSTALL_DIR/wp-content(/.*)?" || true; }
        # Remove the failed vhost from a running Apache without stopping other sites.
        if ((${#VHOST_FILES[@]})) && [[ -n "$WEB_SERVICE" ]]; then
            if [[ "$OS" == alpine ]]; then rc-service "$WEB_SERVICE" reload 2>/dev/null || true
            else systemctl reload "$WEB_SERVICE" 2>/dev/null || true; fi
        fi
        print_error "Installation incomplete. New site resources cleaned up; installed packages retained."
    fi
    [[ -z "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"
    return 0
}

check_existing_wordpress() {
    if [[ -e "$INSTALL_DIR" || -L "$INSTALL_DIR" || -e "$CREDS_FILE" || -L "$CREDS_FILE" ]]; then
        print_error "Refusing to overwrite $INSTALL_DIR or $CREDS_FILE. Back up and migrate existing sites separately."
        return 1
    fi
}

reserve_file() {
    [[ ! -L "$1" ]] && (set -o noclobber; : > "$1") || return 1
    VHOST_FILES+=("$1")
}

backup_file() {
    cp -p -- "$1" "$WORK_DIR/backup-${#BACKUP_FILES[@]}"
    BACKUP_FILES+=("$1")
}

update_repos() {
    if is_debian_based; then apt-get update
    elif is_rhel_based; then dnf makecache
    elif is_arch_based; then print_info "Using installed repository metadata. Run pacman -Syu first if the system needs updating."
    elif is_suse_based; then zypper --non-interactive refresh
    elif [[ "$OS" == alpine ]]; then apk update
    else print_error "Unsupported distribution: $OS"; return 1; fi
}

install_pkg() {
    if is_debian_based; then apt-get install -y "$@"
    elif is_rhel_based; then dnf install -y "$@"
    elif is_arch_based; then pacman -S --needed --noconfirm "$@"
    elif is_suse_based; then zypper --non-interactive install "$@"
    elif [[ "$OS" == alpine ]]; then apk add "$@"
    else return 1; fi
}

# Use the distribution's supported PHP packages, never a guessed version list.
select_packages() {
    BASE_PACKAGES=(curl ca-certificates openssl tar)
    PHP_BIN=php
    if is_debian_based; then
        BASE_PACKAGES+=(apache2 mariadb-server mariadb-client)
        PHP_PACKAGES=(php libapache2-mod-php php-mysql php-curl php-gd php-intl php-mbstring php-xml php-zip)
        WEB_SERVICE=apache2 WEB_USER=www-data WEB_GROUP=www-data
        SITES_AVAILABLE=/etc/apache2/sites-available APACHE_CONF=/etc/apache2/apache2.conf
    elif is_rhel_based; then
        BASE_PACKAGES+=(httpd mod_ssl mariadb-server mariadb policycoreutils-python-utils)
        PHP_PACKAGES=(php php-fpm php-mysqlnd php-gd php-intl php-mbstring php-xml)
        WEB_SERVICE=httpd WEB_USER=apache WEB_GROUP=apache
        SITES_AVAILABLE=/etc/httpd/conf.d APACHE_CONF=/etc/httpd/conf/httpd.conf
    elif is_arch_based; then
        BASE_PACKAGES+=(apache mariadb)
        PHP_PACKAGES=(php php-apache php-gd php-intl)
        WEB_SERVICE=httpd WEB_USER=http WEB_GROUP=http
        SITES_AVAILABLE=/etc/httpd/conf/extra APACHE_CONF=/etc/httpd/conf/httpd.conf
    elif is_suse_based; then
        BASE_PACKAGES+=(apache2 mariadb mariadb-client)
        PHP_PACKAGES=(php8 apache2-mod_php8 php8-mysql php8-curl php8-gd php8-intl php8-mbstring php8-xmlreader php8-xmlwriter php8-zip php8-openssl)
        WEB_SERVICE=apache2 WEB_USER=wwwrun WEB_GROUP=www
        SITES_AVAILABLE=/etc/apache2/vhosts.d APACHE_CONF=/etc/apache2/httpd.conf
    elif [[ "$OS" == alpine ]]; then
        local php_package
        php_package=$(apk search -q 'php[0-9][0-9]' | sort -V | tail -n1)
        [[ "$php_package" =~ ^php[0-9]{2}$ ]] || { print_error "No supported PHP package found; enable Alpine community repository."; return 1; }
        BASE_PACKAGES+=(apache2 apache2-ssl mariadb mariadb-client mariadb-openrc)
        PHP_PACKAGES=("$php_package" "$php_package-apache2" "$php_package-mysqli" "$php_package-curl" "$php_package-gd" "$php_package-intl" "$php_package-mbstring" "$php_package-xml" "$php_package-zip" "$php_package-session" "$php_package-openssl" "$php_package-ctype" "$php_package-dom" "$php_package-fileinfo")
        PHP_BIN=$php_package
        WEB_SERVICE=apache2 WEB_USER=apache WEB_GROUP=apache
        SITES_AVAILABLE=/etc/apache2/conf.d APACHE_CONF=/etc/apache2/httpd.conf
    else print_error "Unsupported distribution: $OS"; return 1; fi
    SSL_DIR=/etc/ssl/vm-setup-wordpress
}

service_start() {
    if [[ "$OS" == alpine ]]; then rc-update add "$1" default; rc-service "$1" start
    else systemctl enable --now "$1"; fi
}

configure_php() {
    if is_debian_based; then
        a2enmod rewrite ssl
        # libapache2-mod-php configures the matching PHP module and prefork MPM.
    elif is_rhel_based; then
        service_start php-fpm
    elif is_arch_based; then
        backup_file "$APACHE_CONF"
        sed -i -E 's/^LoadModule mpm_event_module/#&/; s/^#(LoadModule (mpm_prefork|rewrite|ssl|socache_shmcb)_module)/\1/' "$APACHE_CONF"
        if ! grep -q '^LoadModule php_module ' "$APACHE_CONF"; then
            printf '\nLoadModule php_module modules/libphp.so\nInclude conf/extra/php_module.conf\n' >> "$APACHE_CONF"
        fi
        backup_file /etc/php/php.ini
        sed -i -E 's/^;(extension=(mysqli|curl|gd|intl|zip|pdo_mysql))$/\1/' /etc/php/php.ini
    elif is_suse_based; then
        a2enmod rewrite ssl php8
        a2enflag SSL
    elif [[ "$OS" == alpine ]]; then
        backup_file "$APACHE_CONF"
        sed -i -E 's/^#(LoadModule rewrite_module)/\1/' "$APACHE_CONF"
    fi
    "$PHP_BIN" -r 'exit(version_compare(PHP_VERSION,"8.2",">=") && extension_loaded("mysqli") && extension_loaded("openssl") ? 0 : 1);' || {
        print_error "PHP 8.2+ with mysqli and openssl is required. Check the installed PHP packages."; return 1;
    }
}

validate_domain() {
    [[ "$1" == localhost || "$1" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]
}

download_wordpress() {
    curl --fail --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 20 --max-time 300 --retry 3 \
        https://wordpress.org/latest.tar.gz -o "$WORK_DIR/wordpress.tar.gz"
    # Reject traversal and links before extracting an archive as root.
    tar -tzf "$WORK_DIR/wordpress.tar.gz" > "$WORK_DIR/archive-list"
    awk 'index($0,"wordpress/") != 1 || $0 ~ /(^|\/)\.\.(\/|$)/ { bad=1 } END {exit bad}' "$WORK_DIR/archive-list"
    tar -tvzf "$WORK_DIR/wordpress.tar.gz" > "$WORK_DIR/archive-types"
    awk 'substr($0,1,1) !~ /[-d]/ {bad=1} END {exit bad}' "$WORK_DIR/archive-types"
    mkdir "$WORK_DIR/site"
    tar -xzf "$WORK_DIR/wordpress.tar.gz" --no-same-owner -C "$WORK_DIR/site" --strip-components=1
    [[ -f "$WORK_DIR/site/wp-settings.php" && -f "$WORK_DIR/site/wp-config-sample.php" ]]
}

write_wp_config() {
    local key
    cat > "$INSTALL_DIR/wp-config.php" <<EOF
<?php
define('DB_NAME', '$DB_NAME');
define('DB_USER', '$DB_USER');
define('DB_PASSWORD', '$DB_PASSWORD');
define('DB_HOST', 'localhost');
define('DB_CHARSET', 'utf8mb4');
define('DB_COLLATE', '');
define('DISALLOW_FILE_EDIT', true);
EOF
    for key in AUTH_KEY SECURE_AUTH_KEY LOGGED_IN_KEY NONCE_KEY AUTH_SALT SECURE_AUTH_SALT LOGGED_IN_SALT NONCE_SALT; do
        printf "define('%s', '%s');\n" "$key" "$(openssl rand -hex 32)" >> "$INSTALL_DIR/wp-config.php"
    done
    cat >> "$INSTALL_DIR/wp-config.php" <<'EOF'
$table_prefix = 'wp_';
define('WP_DEBUG', false);
if (!defined('ABSPATH')) { define('ABSPATH', __DIR__ . '/'); }
require_once ABSPATH . 'wp-settings.php';
EOF
    chmod 640 "$INSTALL_DIR/wp-config.php"
    chown "root:$WEB_GROUP" "$INSTALL_DIR/wp-config.php"
    "$PHP_BIN" -l "$INSTALL_DIR/wp-config.php"
}

write_vhost() {
    local vhost="$SITES_AVAILABLE/vm-setup-wordpress.conf"
    reserve_file "$vhost"
    cat > "$vhost" <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN_NAME
    Redirect permanent / https://$DOMAIN_NAME/
</VirtualHost>
<VirtualHost *:443>
    ServerName $DOMAIN_NAME
    DocumentRoot "$INSTALL_DIR"
    DirectoryIndex index.php
    SSLEngine on
    SSLCertificateFile "$SSL_DIR/site.crt"
    SSLCertificateKeyFile "$SSL_DIR/site.key"
    <Directory "$INSTALL_DIR">
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
    chmod 644 "$vhost"
    if is_debian_based; then
        [[ ! -e /etc/apache2/sites-enabled/vm-setup-wordpress.conf && ! -L /etc/apache2/sites-enabled/vm-setup-wordpress.conf ]]
        VHOST_FILES+=(/etc/apache2/sites-enabled/vm-setup-wordpress.conf)
        a2ensite vm-setup-wordpress
    elif is_arch_based; then
        if ! grep -Eq '^[[:space:]]*Listen[[:space:]]+([^[:space:]]*:)?443([[:space:]]|$)' "$APACHE_CONF"; then
            printf '\nListen 443\n' >> "$APACHE_CONF"
        fi
        printf '\nInclude conf/extra/vm-setup-wordpress.conf\n' >> "$APACHE_CONF"
    fi
    apachectl -t
    apachectl -M > "$WORK_DIR/apache-modules"
    grep -Eq 'php_module|php[0-9]_module|proxy_fcgi_module' "$WORK_DIR/apache-modules"
}

main() {
    if [[ "${1:-}" == --help ]]; then
        echo "WordPress $VERSION: new-site installer for Debian/Ubuntu, Alpine, Arch, RHEL/Fedora and SUSE."
        return 0
    fi
    ((EUID == 0)) || { print_error "Run this installer as root."; return 1; }
    umask 077
    check_existing_wordpress
    # shellcheck source=/dev/null
    source /etc/os-release
    OS=$ID
    update_repos
    select_packages
    [[ ! -e "$SSL_DIR" && ! -L "$SSL_DIR" ]]
    [[ ! -e "$SITES_AVAILABLE/vm-setup-wordpress.conf" && ! -L "$SITES_AVAILABLE/vm-setup-wordpress.conf" ]]
    DOMAIN_NAME=${DOMAIN_NAME:-}
    if [[ -z "$DOMAIN_NAME" ]]; then read -r -p 'Domain for this site: ' DOMAIN_NAME; fi
    validate_domain "$DOMAIN_NAME" || { print_error "Invalid domain."; return 1; }
    WORK_DIR=$(mktemp -d /var/tmp/vm-wordpress.XXXXXXXX)
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    install_pkg "${BASE_PACKAGES[@]}" "${PHP_PACKAGES[@]}"
    configure_php
    download_wordpress
    DB_NAME="wp_$(openssl rand -hex 6)" DB_USER="wp_$(openssl rand -hex 6)"
    DB_PASSWORD=$(openssl rand -hex 24)
    if [[ "$OS" == alpine ]] && [[ ! -d /var/lib/mysql/mysql ]]; then
        mariadb-install-db --user=mysql --datadir=/var/lib/mysql
    elif is_arch_based && [[ ! -d /var/lib/mysql/mysql ]]; then
        mariadb-install-db --user=mysql --basedir=/usr --datadir=/var/lib/mysql
    fi
    service_start mariadb
    run_mysql_sql 'SELECT 1;' >/dev/null
    run_mysql_sql "CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    DB_CREATED=true
    run_mysql_sql "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
    DB_USER_CREATED=true
    run_mysql_sql "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';"
    mkdir -p /var/www
    mkdir -m 750 "$INSTALL_DIR"
    SITE_CREATED=true
    cp -a "$WORK_DIR/site/." "$INSTALL_DIR/"
    chown -R "$WEB_USER:$WEB_GROUP" "$INSTALL_DIR"
    find "$INSTALL_DIR" -type d -exec chmod 755 {} +
    find "$INSTALL_DIR" -type f -exec chmod 644 {} +
    write_wp_config
    mkdir -m 755 "$SSL_DIR"
    SSL_CREATED=true
    openssl req -x509 -nodes -days 365 -newkey rsa:3072 -keyout "$SSL_DIR/site.key" -out "$SSL_DIR/site.crt" \
        -subj "/CN=$DOMAIN_NAME" -addext "subjectAltName=DNS:$DOMAIN_NAME"
    chmod 600 "$SSL_DIR/site.key"
    if command -v selinuxenabled >/dev/null && selinuxenabled; then
        semanage fcontext -a -t httpd_sys_rw_content_t "$INSTALL_DIR/wp-content(/.*)?"
        SELINUX_RULE_CREATED=true
        restorecon -R "$INSTALL_DIR" "$SSL_DIR"
    fi
    write_vhost
    (set -o noclobber; : > "$CREDS_FILE")
    CREDS_CREATED=true
    printf 'URL: https://%s\nDatabase: %s\nUser: %s\nPassword: %s\n' "$DOMAIN_NAME" "$DB_NAME" "$DB_USER" "$DB_PASSWORD" > "$CREDS_FILE"
    chmod 600 "$CREDS_FILE"
    service_start "$WEB_SERVICE"
    if [[ "$OS" == alpine ]]; then rc-service "$WEB_SERVICE" restart
    else systemctl restart "$WEB_SERVICE"; fi
    INSTALLATION_FAILED=0
    print_info "WordPress ready at https://$DOMAIN_NAME/wp-admin (self-signed TLS). Credentials: $CREDS_FILE"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
