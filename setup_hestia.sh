#!/bin/bash

# Script Version
SCRIPT_VERSION="1.1.1 (Updated: $(date))"

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

# Helper functions for colored output
function success_message {
    echo -e "\e[32m[SUCCESS]\e[0m $1"
}

function error_message {
    echo -e "\e[31m[ERROR]\e[0m $1"
    echo "$1" >> $ERROR_LOG
}

# Functions
function display_menu {
    echo "Select a category:"
    echo "1) Configuration Management"
    echo "2) Service and DNS Tools"
    echo "3) Exit"
    read -p "Enter your choice [1-3]: " MAIN_CHOICE
    case "$MAIN_CHOICE" in
        1)
            configuration_menu
            ;;
        2)
            service_dns_menu
            ;;
        3)
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
    echo "5) Change admin user for Hestia"
    echo "6) Return to main menu"
    read -p "Enter your choice [1-6]: " CONFIG_CHOICE
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
            change_hestia_admin
            ;;
        6)
            display_menu
            ;;
        *)
            error_message "Invalid choice. Please try again."
            configuration_menu
            ;;
    esac
}

function service_dns_menu {
    echo "Service and DNS Tools:"
    echo "1) Install Hestia Control Panel"
    echo "2) Configure Hestia Domains"
    echo "3) Check services"
    echo "4) Check DNS records"
    echo "5) Fix DNS records"
    echo "6) Return to main menu"
    read -p "Enter your choice [1-6]: " DNS_CHOICE
    case "$DNS_CHOICE" in
        1)
            install_hestia
            ;;
        2)
            configure_hestia_domains
            ;;
        3)
            check_services
            ;;
        4)
            check_dns_records
            ;;
        5)
            fix_dns_records
            ;;
        6)
            display_menu
            ;;
        *)
            error_message "Invalid choice. Please try again."
            service_dns_menu
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
    ssh-keygen -t rsa -b 4096 -f $USER_HOME/.ssh/id_rsa -q -N ""
    cat $USER_HOME/.ssh/id_rsa.pub >> $USER_HOME/.ssh/authorized_keys
    chmod 700 $USER_HOME/.ssh
    chmod 600 $USER_HOME/.ssh/authorized_keys
    chown -R $HESTIA_USER:$HESTIA_USER $USER_HOME/.ssh
    success_message "SSH key authentication configured. Private key is located at $USER_HOME/.ssh/id_rsa."
}

function fix_dns_records {
    echo "Fixing DNS records for subdomains..."
    for SUBDOMAIN in "${REVERSE_DOMAINS[@]}"; do
        EXPECTED_IP="$SERVER_IP"
        if [[ "$SUBDOMAIN" == "proxmox.beanssi.dk" ]]; then
            EXPECTED_IP="$PROXMOX_IP"
        elif [[ "$SUBDOMAIN" == "adguard.beanssi.dk" ]]; then
            EXPECTED_IP="$ADGUARD_IP"
        fi

        echo "Updating DNS for $SUBDOMAIN to point to $EXPECTED_IP..."
        RECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records?type=A&name=$SUBDOMAIN" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" | jq -r '.result[0].id')

        if [ "$RECORD_ID" != "null" ]; then
            curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records/$RECORD_ID" \
                -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
                -H "Content-Type: application/json" \
                --data '{"type":"A","name":"'$SUBDOMAIN'","content":"'$EXPECTED_IP'","ttl":120,"proxied":true}' && \
                success_message "DNS for $SUBDOMAIN updated to $EXPECTED_IP."
        else
            error_message "Failed to update DNS for $SUBDOMAIN. Record not found."
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
    setup_reverse_proxy
    check_services
    check_dns_records

    # Fix DNS records if necessary
    if [ -s $ERROR_LOG ]; then
        echo "Fixing DNS issues detected during setup..."
        fix_dns_records
        echo "Retrying setup after fixing DNS records..."
        setup_reverse_proxy
    fi

    # Display errors if any
    if [ -s $ERROR_LOG ]; then
        error_message "\nErrors and warnings detected during setup:"
        cat $ERROR_LOG
    else
        success_message "\nSetup completed successfully with no errors."
    fi
}

# Display menu
display_menu
