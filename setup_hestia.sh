#!/bin/bash

# Script Version
SCRIPT_VERSION="1.0.6 (Updated: $(date))"
echo "Welcome to Hestia Setup Script - Version $SCRIPT_VERSION"

# Variables
HESTIA_USER="beanssi"
HESTIA_PASSWORD="minmis123"
EMAIL="beanssiii@gmail.com"
DOMAIN="beanssi.dk"
CLOUDFLARE_API_TOKEN="Y45MQapJ7oZ1j9pFf_HpoB7k-218-vZqSJEMKtD3"
CLOUDFLARE_ZONE_ID="9de910e45e803b9d6012834bbc70223c"
REVERSE_DOMAINS=("proxmox.beanssi.dk" "hestia.beanssi.dk" "beanssi.dk" "adguard.beanssi.dk")
SERVER_IP="192.168.50.51"
PROXMOX_IP="192.168.50.50"
ADGUARD_IP="192.168.50.52"

# Log Setup Details
LOGFILE=/var/log/setup_hestia.log
ERROR_LOG="/var/log/setup_hestia_errors.log"
> $ERROR_LOG # Clear the error log at the start of the script
exec > >(tee -a $LOGFILE) 2>&1

# Add Hestia to PATH
export PATH=$PATH:/usr/local/hestia/bin

# Functions
function display_menu {
    echo "Select an action to perform:"
    echo "1) Backup configurations"
    echo "2) Install Fail2Ban"
    echo "3) Configure SSH key"
    echo "4) Full setup"
    echo "5) Check services"
    echo "6) Check DNS records"
    echo "7) Exit"
    read -p "Enter your choice [1-7]: " CHOICE
    case "$CHOICE" in
        1)
            backup_configurations
            ;;
        2)
            install_fail2ban
            ;;
        3)
            configure_ssh_key
            ;;
        4)
            full_setup
            ;;
        5)
            check_services
            ;;
        6)
            check_dns_records
            ;;
        7)
            echo "Exiting script."
            exit 0
            ;;
        *)
            echo "Invalid choice. Please try again."
            display_menu
            ;;
    esac
}

function log_error {
    echo "$1" >> $ERROR_LOG
}

function backup_configurations {
    echo "Backing up critical configurations..."
    BACKUP_DIR="/var/backups/setup_hestia"
    mkdir -p $BACKUP_DIR
    cp -r /etc/nginx $BACKUP_DIR/nginx_backup
    cp -r /etc/letsencrypt $BACKUP_DIR/letsencrypt_backup
    cp /etc/vsftpd.conf $BACKUP_DIR/vsftpd.conf.backup
    echo "Backup completed. Files are stored in $BACKUP_DIR."
}

function install_fail2ban {
    echo "Installing and configuring Fail2Ban..."
    apt update
    apt install fail2ban -y
    systemctl enable fail2ban
    systemctl start fail2ban
    echo "Fail2Ban is installed and running."
}

function configure_ssh_key {
    echo "Configuring SSH key authentication for user $HESTIA_USER..."
    if ! id "$HESTIA_USER" &>/dev/null; then
        echo "User $HESTIA_USER does not exist. Creating user..."
        useradd -m -s /bin/bash $HESTIA_USER
        echo "$HESTIA_USER:$HESTIA_PASSWORD" | chpasswd
        echo "User $HESTIA_USER created."
    fi

    USER_HOME="/home/$HESTIA_USER"
    mkdir -p $USER_HOME/.ssh
    ssh-keygen -t rsa -b 4096 -f $USER_HOME/.ssh/id_rsa -q -N ""
    cat $USER_HOME/.ssh/id_rsa.pub >> $USER_HOME/.ssh/authorized_keys
    chmod 700 $USER_HOME/.ssh
    chmod 600 $USER_HOME/.ssh/authorized_keys
    chown -R $HESTIA_USER:$HESTIA_USER $USER_HOME/.ssh
    echo "SSH key authentication configured. Private key is located at $USER_HOME/.ssh/id_rsa."
}

function generate_sftp_config {
    echo "Generating SFTP configuration for VS Code..."
    SFTP_CONFIG_FILE="/root/sftp-config-vscode.json"
    cat > $SFTP_CONFIG_FILE <<EOL
{
    "name": "SFTP Connection",
    "host": "$(curl -s ifconfig.me)",
    "protocol": "sftp",
    "port": 22,
    "username": "$HESTIA_USER",
    "privateKeyPath": "/home/$HESTIA_USER/.ssh/id_rsa",
    "remotePath": "/home/$HESTIA_USER/",
    "uploadOnSave": true
}
EOL
    echo "SFTP configuration for VS Code has been generated at $SFTP_CONFIG_FILE."
}

function check_hestia_installation {
    if [ -d "/usr/local/hestia" ]; then
        echo "Hestia Control Panel is already installed. Skipping installation."
        return 1
    else
        return 0
    fi
}

function install_hestia {
    if check_hestia_installation; then
        echo "Installing Hestia Control Panel..."
        apt update
        wget https://raw.githubusercontent.com/hestiacp/hestiacp/release/install/hst-install.sh
        bash hst-install.sh --force --email $EMAIL --password $HESTIA_PASSWORD --hostname "hestia.$DOMAIN" --lang en -y --no-reboot
        echo "Hestia installation completed."
    fi
}

function configure_certbot_plugin {
    echo "Ensuring Certbot Nginx plugin is installed..."
    apt install certbot python3-certbot-nginx -y
}

function setup_reverse_proxy {
    echo "Setting up reverse proxy and SSL certificates..."
    for SUBDOMAIN in "${REVERSE_DOMAINS[@]}"; do
        if ! certbot --nginx --redirect -d $SUBDOMAIN --non-interactive --agree-tos -m $EMAIL; then
            log_error "Error: Certificate for $SUBDOMAIN was not issued. Check Certbot logs for details."
        else
            echo "Certificate for $SUBDOMAIN successfully issued."
        fi
    done
    nginx -t && systemctl reload nginx || log_error "Error: Failed to reload Nginx. Check configuration."
}

function add_domains_to_hestia {
    echo "Adding domains to Hestia Control Panel..."

    # Ensure user exists in Hestia
    if ! /usr/local/hestia/bin/v-list-user $HESTIA_USER &>/dev/null; then
        echo "Hestia user $HESTIA_USER does not exist. Creating user..."
        /usr/local/hestia/bin/v-add-user $HESTIA_USER $HESTIA_PASSWORD $EMAIL
        echo "User $HESTIA_USER created successfully."
    fi

    for SUBDOMAIN in "${REVERSE_DOMAINS[@]}"; do
        echo "Executing: /usr/local/hestia/bin/v-add-web-domain $HESTIA_USER $SUBDOMAIN"
        if /usr/local/hestia/bin/v-list-web-domain $HESTIA_USER $SUBDOMAIN &>/dev/null; then
            echo "$SUBDOMAIN already exists in Hestia. Skipping."
        else
            /usr/local/hestia/bin/v-add-web-domain $HESTIA_USER $SUBDOMAIN
            /usr/local/hestia/bin/v-add-letsencrypt-domain $HESTIA_USER $SUBDOMAIN
            echo "$SUBDOMAIN has been added to Hestia with SSL."
        fi
    done
}

function check_services {
    echo "Checking critical services..."
    SERVICES=("fail2ban" "nginx" "vsftpd" "hestia")
    for SERVICE in "${SERVICES[@]}"; do
        if systemctl is-active --quiet $SERVICE; then
            echo "Service $SERVICE is running."
        else
            ERROR_MSG="Service $SERVICE is NOT running. Attempting to start..."
            echo "$ERROR_MSG"
            log_error "$ERROR_MSG"
            systemctl start $SERVICE
            if systemctl is-active --quiet $SERVICE; then
                echo "Service $SERVICE started successfully."
            else
                log_error "Failed to start service $SERVICE. Please check manually."
            fi
        fi
    done
}

function check_dns_records {
    echo "Checking DNS records for subdomains..."
    for SUBDOMAIN in "${REVERSE_DOMAINS[@]}"; do
        EXPECTED_IP="$SERVER_IP"
        if [[ "$SUBDOMAIN" == "proxmox.beanssi.dk" ]]; then
            EXPECTED_IP="$PROXMOX_IP"
        elif [[ "$SUBDOMAIN" == "adguard.beanssi.dk" ]]; then
            EXPECTED_IP="$ADGUARD_IP"
        fi

        DNS_IP=$(nslookup $SUBDOMAIN | grep -A1 "Name:" | tail -n1 | awk '{print $2}')
        if [ "$DNS_IP" == "$EXPECTED_IP" ]; then
            echo "DNS for $SUBDOMAIN is correctly configured ($DNS_IP)."
        else
            WARNING_MSG="Warning: DNS for $SUBDOMAIN is misconfigured. Expected $EXPECTED_IP but found $DNS_IP."
            echo "$WARNING_MSG"
            log_error "$WARNING_MSG"
        fi
    done
}

function full_setup {
    echo "Starting full setup..."
    backup_configurations
    install_fail2ban
    configure_certbot_plugin
    configure_ssh_key
    generate_sftp_config
    install_hestia
    add_domains_to_hestia
    setup_reverse_proxy
    check_services
    check_dns_records

    # Display errors if any
    if [ -s $ERROR_LOG ]; then
        echo -e "\nErrors and warnings detected during setup:"
        cat $ERROR_LOG
    else
        echo -e "\nSetup completed successfully with no errors."
    fi
}

# Display menu
display_menu


# Final message
echo "Setup script completed with the selected option."
