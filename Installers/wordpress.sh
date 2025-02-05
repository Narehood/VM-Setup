#!/bin/sh

install_dir="/var/www/html"
# Creating Random WP Database Credentials
db_name="wp`date +%s`"
db_user=$db_name
db_password=`date | md5sum | cut -c '1-12'`
sleep 1
mysqlrootpass=`date | md5sum | cut -c '1-12'`
sleep 1

# Install Packages for https and mysql
apt -y update 
apt -y upgrade
apt -y install apache2
apt -y install mysql-server

# Start http
rm /var/www/html/index.html
systemctl enable apache2
systemctl start apache2

# Start mysql and set root password
systemctl enable mysql
systemctl start mysql

/usr/bin/mysql -e "USE mysql;"
/usr/bin/mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$mysqlrootpass';"
/usr/bin/mysql -e "FLUSH PRIVILEGES;"
touch /root/.my.cnf
chmod 640 /root/.my.cnf
echo "[client]" >> /root/.my.cnf
echo "user=root" >> /root/.my.cnf
echo "password=$mysqlrootpass" >> /root/.my.cnf

# Install PHP
apt -y install php php-bz2 php-mysqli php-curl php-gd php-intl php-common php-mbstring php-xml

sed -i '0,/AllowOverride\ None/! {0,/AllowOverride\ None/ s/AllowOverride\ None/AllowOverride\ All/}' /etc/apache2/apache2.conf # Allow htaccess usage

systemctl restart apache2

# Download and extract latest WordPress Package
if [ ! -f /tmp/latest.tar.gz ]; then
    echo "Downloading WordPress"
    cd /tmp/ && wget "http://wordpress.org/latest.tar.gz" || { echo "Download failed"; exit 1; }
else
    echo "WP is already downloaded."
fi

/bin/tar -C "$install_dir" -zxf /tmp/latest.tar.gz --strip-components=1
chown www-data: "$install_dir" -R

# Create WP-config and set DB credentials
/bin/mv "$install_dir/wp-config-sample.php" "$install_dir/wp-config.php"

/bin/sed -i "s/database_name_here/$db_name/g" "$install_dir/wp-config.php"
/bin/sed -i "s/username_here/$db_user/g" "$install_dir/wp-config.php"
/bin/sed -i "s/password_here/$db_password/g" "$install_dir/wp-config.php"

cat << EOF >> "$install_dir/wp-config.php"
define('FS_METHOD', 'direct');
EOF

cat << EOF >> "$install_dir/.htaccess"
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
RewriteRule ^index.php$ – [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule
