#!/bin/bash

# Variables
HESTIA_USER="beans"
HESTIA_PASSWORD="Denver1234"
EMAIL="beanssiii@gmail.com"
DOMAIN="beanssi.dk"
CLOUDFLARE_API_TOKEN="Y45MQapJ7oZ1j9pFf_HpoB7k-218-vZqSJEMKtD3"
CLOUDFLARE_ZONE_ID="9de910e45e803b9d6012834bbc70223c"
REVERSE_DOMAINS=("proxmox.beanssi.dk" "hestia.beanssi.dk" "beanssi.dk" "adguard.beanssi.dk")

# Log Setup Details
LOGFILE=/var/log/setup_hestia.log
exec > >(tee -a $LOGFILE) 2>&1

# Functions
function display_menu {
    echo "Select an action to perform:"
    echo "1) Backup configurations"
    echo "2) Install Fail2Ban"
    echo "3) Configure SSH key"
    echo "4) Full setup"
    echo "5) Exit"
    read -p "Enter your choice [1-5]: " CHOICE
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
            echo "Exiting script."
            exit 0
            ;;
        *)
            echo "Invalid choice. Please try again."
            display_menu
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
    echo "Backup completed. Files are stored in $BACKUP_DIR."
}

function install_fail2ban {
    echo "Installing and configuring Fail2Ban..."
    apt install fail2ban -y
    systemctl enable fail2ban
    systemctl start fail2ban
    echo "Fail2Ban is installed and running."
}

function configure_ssh_key {
    echo "Configuring SSH key authentication for user $HESTIA_USER..."
    if id "$HESTIA_USER" &>/dev/null; then
        USER_HOME="/home/$HESTIA_USER"
        mkdir -p $USER_HOME/.ssh
        ssh-keygen -t rsa -b 4096 -f $USER_HOME/.ssh/id_rsa -q -N ""
        cat $USER_HOME/.ssh/id_rsa.pub >> $USER_HOME/.ssh/authorized_keys
        chmod 700 $USER_HOME/.ssh
        chmod 600 $USER_HOME/.ssh/authorized_keys
        chown -R $HESTIA_USER:$HESTIA_USER $USER_HOME/.ssh
        echo "SSH key authentication configured. Private key is located at $USER_HOME/.ssh/id_rsa."
    else
        echo "Error: User $HESTIA_USER does not exist. Skipping SSH key configuration."
    fi
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
        wget https://raw.githubusercontent.com/hestiacp/hestiacp/release/install/hst-install.sh
        bash hst-install.sh --force --email $EMAIL --password $HESTIA_PASSWORD --hostname "hestia.$DOMAIN" --lang en -y --no-reboot
        echo "Hestia installation completed."
    fi
}

function configure_certbot_plugin {
    echo "Ensuring Certbot Nginx plugin is installed..."
    apt install python3-certbot-nginx -y
}

function setup_reverse_proxy {
    echo "Setting up reverse proxy and SSL certificates..."
    for SUBDOMAIN in "${REVERSE_DOMAINS[@]}"; do
        if [ "$SUBDOMAIN" == "proxmox.beanssi.dk" ]; then
            PROXY_PASS="https://192.168.50.50:8006"
        elif [ "$SUBDOMAIN" == "hestia.beanssi.dk" ]; then
            PROXY_PASS="https://192.168.50.51:8083"
        elif [ "$SUBDOMAIN" == "adguard.beanssi.dk" ]; then
            PROXY_PASS="http://192.168.50.52"
        elif [ "$SUBDOMAIN" == "beanssi.dk" ]; then
            cat > "/etc/nginx/sites-available/$SUBDOMAIN" <<EOL
server {
    listen 80;
    server_name $SUBDOMAIN;

    location / {
        root /var/www/html;
        index index.html;
    }
}
EOL
            ln -sf "/etc/nginx/sites-available/$SUBDOMAIN" "/etc/nginx/sites-enabled/"
            continue
        else
            PROXY_PASS="https://192.168.50.51"
        fi

        cat > "/etc/nginx/sites-available/$SUBDOMAIN" <<EOL
server {
    listen 80;
    server_name $SUBDOMAIN;

    location / {
        proxy_pass $PROXY_PASS;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOL
        ln -sf "/etc/nginx/sites-available/$SUBDOMAIN" "/etc/nginx/sites-enabled/"
        certbot --nginx -d $SUBDOMAIN --non-interactive --agree-tos -m $EMAIL || {
            echo "Error: Certificate for $SUBDOMAIN was not issued. Check Certbot logs for details.";
            continue;
        }
    done
    nginx -t && systemctl reload nginx
}

function full_setup {
    echo "Starting full setup..."
    backup_configurations
    install_fail2ban
    configure_certbot_plugin
    configure_ssh_key
    install_hestia
    setup_reverse_proxy

    echo "Full setup completed."
}

# Display menu
display_menu

# Final message
echo "Setup script completed with the selected option."
