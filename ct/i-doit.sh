#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/MichaelOv/ProxmoxVE/refs/heads/idoit/misc/build.func)
# Copyright (c) 2021-2024 community-scripts ORG
# Author: [YourUserName]
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: [SOURCE_URL]

# App Default Values
APP="i-doit"
TAGS="asset-management;cmdb;foss"
var_cpu="2"
var_ram="2048"
var_disk="6"
var_os="debian"
var_version="12"
var_unprivileged="1"

# App Output & Base Settings
header_info "$APP"
base_settings

# Core
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources
    # Check if installation is present | -f for file, -d for folder
    if [[ ! -f [/var/www/html/i-doit/] ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi

    # Crawling the new version and checking whether an update is required
    RELEASE=$(curl -s https://i-doit.com/updates.xml | grep -oP '(?<=<directory>)[^<]+' | tail -n1)
    if [[ ! -f /var/www/html/i-doit/updates/version/${RELEASE} ]]; then
        msg_info "Updating $APP to v${RELEASE}"

        # Stopping Services
        #msg_info "Stopping $APP"
        #systemctl stop [SERVICE_NAME]
        #msg_ok "Stopped $APP"

        # Creating Backup
        msg_info "Creating Backup"
        mysqldump -hlocalhost -uroot -p --all-databases > /var/www/html/backup/backup.sql
        tar -czf "/var/www/html/backup/${APP}_backup_$(date +%F).tar.gz" "/var/www/html/i-doit/"
        msg_ok "Backup Created"

        # Execute Update
        msg_info "Updating $APP to v${RELEASE}"
        #[UPDATE_COMMANDS]
        msg_ok "Updated $APP to v${RELEASE}"

        # Starting Services
        #msg_info "Starting $APP"
        #systemctl start [SERVICE_NAME]
        #sleep 2
        #msg_ok "Started $APP"

        # Cleaning up
        #msg_info "Cleaning Up"
        #rm -rf [TEMP_FILES]
        #msg_ok "Cleanup Completed"

        # Last Action
        echo "${RELEASE}" >/opt/${APP}_version.txt
        msg_ok "Update Successful"
    else
        msg_ok "No update required. ${APP} is already at v${RELEASE}"
    fi
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:80${CL}"
