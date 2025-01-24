#!/bin/bash

# Script Version
SCRIPT_VERSION="1.1.8 (Updated: $(date))"

echo "Welcome to Hestia Setup Script - Version $SCRIPT_VERSION"

# Variables
USE_PUBLIC_IP=false # Always use local IPs in this setup

HESTIA_USER="beanssi"
HESTIA_PASSWORD="minmis123"
EMAIL="beanssiii@gmail.com"
DOMAIN="beanssi.dk"
CLOUDFLARE_API_TOKEN="Y45MQapJ7oZ1j9pFf_HpoB7k-218-vZqSJEMKtD3"
CLOUDFLARE_ZONE_ID="9de910e45e803b9d6012834bbc70223c"
REVERSE_DOMAINS=("proxmox.beanssi.dk" "hestia.beanssi.dk" "beanssi.dk" "adguard.beanssi.dk")

# Local IPs for reverse proxy
SERVER_IP="192.168.50.51"
PROXMOX_IP="192.168.50.50"
ADGUARD_IP="192.168.50.52"
LOCAL_DNS_SERVER="$SERVER_IP" # Use AdGuard or local DNS server

# Log Setup Details
LOGFILE=/var/log/setup_hestia.log
ERROR_LOG="/var/log/setup_hestia_errors.log"
> $ERROR_LOG # Clear the error log at the start of the script
exec > >(tee -a $LOGFILE) 2>&1

# Add Hestia to PATH
export PATH=$PATH:/usr/local/hestia/bin

# Helper functions for colored output
function success_message {
    echo -e "\e[32m[SUCCESS]\e[0m $1"
}

function error_message {
    echo -e "\e[31m[ERROR]\e[0m $1"
    echo "$1" >> $ERROR_LOG
}

# Functions
function create_nginx_config {
    SUBDOMAIN=$1
    TARGET_IP=$2
    PORT=${3:-80} # Default to port 80 if not specified

    CONFIG_FILE="/etc/nginx/conf.d/$SUBDOMAIN.conf"
    echo "Creating nginx configuration for $SUBDOMAIN..."

    cat > $CONFIG_FILE <<EOL
server {
    listen 80;
    server_name $SUBDOMAIN;

    location / {
        proxy_pass http://$TARGET_IP:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    error_log /var/log/nginx/$SUBDOMAIN-error.log;
    access_log /var/log/nginx/$SUBDOMAIN-access.log;
}
EOL

    if nginx -t; then
        success_message "Nginx configuration for $SUBDOMAIN created successfully."
        systemctl reload nginx
    else
        error_message "Failed to create nginx configuration for $SUBDOMAIN."
    fi
}

function setup_reverse_proxy {
    echo "Setting up reverse proxy configurations..."
    create_nginx_config "proxmox.beanssi.dk" "$PROXMOX_IP" 8006
    create_nginx_config "hestia.beanssi.dk" "$SERVER_IP" 8083
    create_nginx_config "beanssi.dk" "$SERVER_IP"
    create_nginx_config "adguard.beanssi.dk" "$ADGUARD_IP" 3000
}

function display_menu {
    echo "Select a category:"
    echo "1) Configuration Management"
    echo "2) DNS and Certificate Management"
    echo "3) Reverse Proxy Management"
    echo "4) Exit"
    read -p "Enter your choice [1-4]: " MAIN_CHOICE
    case "$MAIN_CHOICE" in
        1)
            configuration_menu
            ;;
        2)
            dns_certificate_menu
            ;;
        3)
            setup_reverse_proxy
            ;;
        4)
            echo "Exiting script."
            exit 0
            ;;
        *)
            error_message "Invalid choice. Please try again."
            display_menu
            ;;
    esac
}

function configuration_menu {
    echo "Configuration Management Options:"
    echo "1) Backup configurations"
    echo "2) Install Fail2Ban"
    echo "3) Configure SSH key"
    echo "4) Full setup"
    echo "5) Return to main menu"
    read -p "Enter your choice [1-5]: " CONFIG_CHOICE
    case "$CONFIG_CHOICE" in
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
            display_menu
            ;;
        *)
            error_message "Invalid choice. Please try again."
            configuration_menu
            ;;
    esac
}

function dns_certificate_menu {
    echo "DNS and Certificate Management Options:"
    echo "1) Setup DNS records"
    echo "2) Setup SSL certificates"
    echo "3) Check DNS records"
    echo "4) Return to main menu"
    read -p "Enter your choice [1-4]: " DNS_CHOICE
    case "$DNS_CHOICE" in
        1)
            setup_dns
            ;;
        2)
            setup_certificates
            ;;
        3)
            check_dns_records
            ;;
        4)
            display_menu
            ;;
        *)
            error_message "Invalid choice. Please try again."
            dns_certificate_menu
            ;;
    esac
}

function backup_configurations {
    echo "Backing up critical configurations..."
    BACKUP_DIR="/var/backups/setup_hestia"
    mkdir -p $BACKUP_DIR
    cp -r /etc/nginx $BACKUP_DIR/nginx_backup
    cp -r /etc/letsencrypt $BACKUP_DIR/letsencrypt_backup
    cp /etc/vsftpd.conf $BACKUP_DIR/vsftpd.conf.backup
    success_message "Backup completed. Files are stored in $BACKUP_DIR."
}

function install_fail2ban {
    echo "Installing and configuring Fail2Ban..."
    apt update
    apt install fail2ban -y
    systemctl enable fail2ban
    systemctl start fail2ban
    success_message "Fail2Ban is installed and running."
}

function configure_certbot_plugin {
    echo "Ensuring Certbot Nginx plugin is installed..."
    apt install certbot python3-certbot-nginx -y
    success_message "Certbot and Nginx plugin installed."
}

function configure_ssh_key {
    echo "Configuring SSH key authentication for user $HESTIA_USER..."
    if id "$HESTIA_USER" &>/dev/null; then
        echo "User $HESTIA_USER already exists. Skipping user creation."
    else
        echo "User $HESTIA_USER does not exist. Creating user..."
        useradd -m -s /bin/bash $HESTIA_USER
        echo "$HESTIA_USER:$HESTIA_PASSWORD" | chpasswd
        success_message "User $HESTIA_USER created."
    fi

    USER_HOME="/home/$HESTIA_USER"
    mkdir -p $USER_HOME/.ssh
    yes | ssh-keygen -t rsa -b 4096 -f $USER_HOME/.ssh/id_rsa -q -N ""
    cat $USER_HOME/.ssh/id_rsa.pub >> $USER_HOME/.ssh/authorized_keys
    chmod 700 $USER_HOME/.ssh
    chmod 600 $USER_HOME/.ssh/authorized_keys
    chown -R $HESTIA_USER:$HESTIA_USER $USER_HOME/.ssh
    success_message "SSH key authentication configured. Private key is located at $USER_HOME/.ssh/id_rsa."
}

function full_setup {
    echo "Starting full setup..."
    backup_configurations
    install_fail2ban
    configure_certbot_plugin
    configure_ssh_key
    setup_dns
    setup_reverse_proxy
    setup_certificates

    # Check DNS and retry certificates if necessary
    check_dns_records
    if [ -s $ERROR_LOG ]; then
        echo "Retrying SSL certificates after DNS fixes..."
        setup_certificates
    fi

    # Final check for errors
    if [ -s $ERROR_LOG ]; then
        error_message "\nErrors and warnings detected during setup:"
        cat $ERROR_LOG
    else
        success_message "\nSetup completed successfully with no errors."
    fi
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

        DNS_IP=$(dig @$LOCAL_DNS_SERVER +short $SUBDOMAIN | tail -n1)
        if [ "$DNS_IP" == "$EXPECTED_IP" ]; then
            success_message "DNS for $SUBDOMAIN is correctly configured ($DNS_IP)."
        else
            error_message "DNS for $SUBDOMAIN is misconfigured. Expected $EXPECTED_IP but found $DNS_IP."
            update_dns_record "$SUBDOMAIN" "$EXPECTED_IP"
        fi
    done
}

function update_dns_record {
    SUBDOMAIN=$1
    EXPECTED_IP=$2

    echo "Updating DNS record for $SUBDOMAIN to $EXPECTED_IP..."
    RECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records?type=A&name=$SUBDOMAIN" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" | jq -r '.result[0].id')

    if [ "$RECORD_ID" == "null" ] || [ -z "$RECORD_ID" ]; then
        echo "No DNS record found for $SUBDOMAIN. Creating a new record..."
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data '{"type":"A","name":"'$SUBDOMAIN'","content":"'$EXPECTED_IP'","ttl":120,"proxied":true}' && \
            success_message "DNS record created for $SUBDOMAIN pointing to $EXPECTED_IP."
    else
        echo "Updating existing DNS record for $SUBDOMAIN..."
        curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records/$RECORD_ID" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data '{"type":"A","name":"'$SUBDOMAIN'","content":"'$EXPECTED_IP'","ttl":120,"proxied":true}' && \
            success_message "DNS record for $SUBDOMAIN updated to $EXPECTED_IP."
    fi
}

function setup_dns {
    echo "Setting up DNS records for all subdomains..."
    for SUBDOMAIN in "${REVERSE_DOMAINS[@]}"; do
        EXPECTED_IP="$SERVER_IP"
        if [[ "$SUBDOMAIN" == "proxmox.beanssi.dk" ]]; then
            EXPECTED_IP="$PROXMOX_IP"
        elif [[ "$SUBDOMAIN" == "adguard.beanssi.dk" ]]; then
            EXPECTED_IP="$ADGUARD_IP"
        fi

        update_dns_record "$SUBDOMAIN" "$EXPECTED_IP"
    done
}

function setup_certificates {
    echo "Setting up SSL certificates for all subdomains..."
    for SUBDOMAIN in "${REVERSE_DOMAINS[@]}"; do
        echo "Issuing SSL certificate for $SUBDOMAIN..."
        if certbot --nginx --redirect -d "$SUBDOMAIN" --non-interactive --agree-tos -m "$EMAIL"; then
            success_message "SSL certificate issued successfully for $SUBDOMAIN."
        else
            error_message "Failed to issue SSL certificate for $SUBDOMAIN. Check Certbot logs."
        fi
    done
}

# Display menu
display_menu
