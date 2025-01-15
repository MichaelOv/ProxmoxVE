#!/usr/bin/env bash

# Copyright (c) 2021-2024 community-scripts ORG
# Author: [YourUserName]
# License: MIT
# Source: [SOURCE_URL]

# Import Functions und Setup
source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Installing Dependencies with the 3 core dependencies (curl;sudo;mc)
msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  sudo \
  apache2 \
  mariadb-server \
  memcached \
  moreutils \
  unzip \
  php-{bcmath,cli,common,curl,gd,fpm,imagick,ldap,mbstring,memcached,mysql,pgsql,soap,xml,zip}
msg_ok "Installed Dependencies"

# Configuring MariaDB
msg_info "Configuring MariaDB"
ROOT_DB_PASS=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c13)
IDOIT_DB_USER=idoit
IDOIT_DB_PASS=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c13)
{
    echo "MariaDB-Credentials"
    echo "Username: $USERNAME"
    echo "Password: $ROOT_DB_PASS"
    echo ""
    echo "i-doit Mariadb user"
    echo "Username: $IDOIT_DB_USER"
    echo "Password: $IDOIT_DB_PASS"
} >> ~/application.creds
cat <<EOF >/etc/mysql/mariadb.conf.d/99-i-doit.cnf
[mysqld]
# This is the number 1 setting to look at for any performance optimization
# It is where the data and indexes are cached: having it as large as possible will
# ensure MySQL uses memory and not disks for most read operations.
# See https://mariadb.com/kb/en/innodb-buffer-pool/
# Typical values are 1G (1-2GB RAM), 5-6G (8GB RAM), 20-25G (32GB RAM), 100-120G (128GB RAM).
innodb_buffer_pool_size = 1G
# Redo log file size, the higher the better.
# MySQL/MariaDB writes one of these log files in a default installation.
innodb_log_file_size = 512M
innodb_sort_buffer_size = 64M
sort_buffer_size = 262144 # default
join_buffer_size = 262144 # default
max_allowed_packet = 128M
max_heap_table_size = 32M
query_cache_min_res_unit = 4096
query_cache_type = 1
query_cache_limit = 5M
query_cache_size = 80M
tmp_table_size = 32M
max_connections = 200
innodb_file_per_table = 1
# Disable this (= 0) if you have slow hard disks
innodb_flush_log_at_trx_commit = 1
innodb_flush_method = O_DIRECT
innodb_lru_scan_depth = 2048
table_definition_cache = 1024
table_open_cache = 2048
innodb_stats_on_metadata = 0
sql-mode = ""
EOF
mysql -u root -e "SET GLOBAL innodb_fast_shutdown = 0;"
mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('${ROOT_DB_PASS}');"
systemctl restart mariadb
msg_ok "Configured MariaDB"

# Configuring PHP
msg_info "Configuring PHP"
cat <<EOF >/etc/php/8.2/mods-available/i-doit.ini
allow_url_fopen = Yes
file_uploads = On
magic_quotes_gpc = Off
max_execution_time = 300
max_file_uploads = 42
max_input_time = 60
max_input_vars = 10000
memory_limit = 256M
post_max_size = 128M
register_argc_argv = On
register_globals = Off
short_open_tag = On
upload_max_filesize = 128M
display_errors = Off
display_startup_errors = Off
error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT
log_errors = On
default_charset = "UTF-8"
default_socket_timeout = 60
date.timezone = Europe/Berlin
session.gc_maxlifetime = 604800
session.cookie_lifetime = 0
mysqli.default_socket = /var/run/mysqld/mysqld.sock
EOF
phpenmod i-doit
systemctl restart php8.2-fpm
msg_ok "Configured PHP"

# Configuring Apache2
msg_info "Configuring Apache2"
a2dissite 000-default
cat <<EOF >/etc/apache2/sites-available/i-doit.conf
ServerName ${hostname}

<VirtualHost *:80>
    ServerAdmin i-doit@example.net

    DirectoryIndex index.php
    DocumentRoot /var/www/html/i-doit/

    <Directory /var/www/html/i-doit/>
        AllowOverride All
    </Directory>

    TimeOut 600
    ProxyTimeout 600

    <FilesMatch "\\.php$">
        <If "-f %{REQUEST_FILENAME}">
            SetHandler "proxy:unix:/var/run/php/php8.2-fpm.sock|fcgi://localhost"
        </If>
    </FilesMatch>

    LogLevel warn
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF
a2ensite i-doit &>/dev/null
a2enmod rewrite proxy proxy_fcgi &>/dev/null
systemctl restart apache2 &>/dev/null
msg_ok "Configured Apache2"

# Setup i-doit
msg_info "Setup i-doit"
cd /var/www/html
RELEASE=$(curl -s https://i-doit.com/updates.xml | grep -oP '(?<=<directory>)[^<]+' | tail -n1)
wget -q "https://login.i-doit.com/downloads/idoit-${RELEASE}.zip"
unzip -q idoit-${RELEASE}.zip -d i-doit
cd i-doit
ADMIN_CENTER_PASS=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c13)
sudo -u www-data php console.php install \
        --root-user root \
        --root-password "${ROOT_DB_PASS}" \
        --host localhost \
        --database idoit_system \
        --user "${IDOIT_DB_USER}" \
        --password "${IDOIT_DB_PASS}" \
        --admin-password "${ADMIN_CENTER_PASS}" \
        -n &>/dev/null
msg_ok "Setting up i-doit done"
# Creating i-doit tenant
msg_info "Creating i-doit tenant"
sudo -u www-data php console.php install \
        --root-user root \
        --root-password "${ROOT_DB_PASS}" \
        -d idoit_data \
        -t "Default" \
        --user "${IDOIT_DB_USER}" \
        --password "${IDOIT_DB_PASS}" \
        -n &>/dev/null
msg_info "Created i-doit tenant"
# 
#
echo "${RELEASE}" >/var/www/html/i-doit/${APPLICATION}_version.txt
msg_ok "Setup ${APPLICATION}"

# Creating Service (if needed)
#msg_info "Creating Service"
#cat <<EOF >/etc/systemd/system/${APPLICATION}.service
#[Unit]
#Description=${APPLICATION} Service
#After=network.target
#
#[Service]
#ExecStart=[START_COMMAND]
#Restart=always
#
#[Install]
#WantedBy=multi-user.target
#EOF
#systemctl enable -q --now ${APPLICATION}.service
#msg_ok "Created Service"

motd_ssh
customize

# Cleanup
msg_info "Cleaning up"
rm -f /var/www/html/i-doit-${RELEASE}.zip
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
