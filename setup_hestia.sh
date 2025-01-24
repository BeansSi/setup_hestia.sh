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
    USER_HOME="/home/$HESTIA_USER"
    mkdir -p $USER_HOME/.ssh
    ssh-keygen -t rsa -b 4096 -f $USER_HOME/.ssh/id_rsa -q -N ""
    cat $USER_HOME/.ssh/id_rsa.pub >> $USER_HOME/.ssh/authorized_keys
    chmod 700 $USER_HOME/.ssh
    chmod 600 $USER_HOME/.ssh/authorized_keys
    chown -R $HESTIA_USER:$HESTIA_USER $USER_HOME/.ssh
    echo "SSH key authentication configured. Private key is located at $USER_HOME/.ssh/id_rsa."
}

function full_setup {
    echo "Starting full setup..."
    backup_configurations
    install_fail2ban
    configure_ssh_key

    # Update server
    echo "Updating server..."
    apt update && apt upgrade -y

    # Install necessary packages
    echo "Installing required packages..."
    apt install -y curl wget ufw nginx certbot vsftpd

    # Install Hestia Control Panel
    echo "Installing Hestia Control Panel..."
    wget https://raw.githubusercontent.com/hestiacp/hestiacp/release/install/hst-install.sh
    bash hst-install.sh --force --email $EMAIL --password $HESTIA_PASSWORD --hostname "hestia.$DOMAIN" --lang en

    # Create Hestia user
    echo "Creating Hestia user..."
    v-add-user $HESTIA_USER $HESTIA_PASSWORD $EMAIL

    # Setup Firewall Rules
    echo "Configuring firewall rules..."
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow 8006/tcp
    ufw allow 21/tcp
    ufw enable

    # Configure FTP for VS Code Access
    echo "Configuring FTP server..."
    cat > /etc/vsftpd.conf <<EOL
listen=YES
local_enable=YES
write_enable=YES
chroot_local_user=YES
allow_writeable_chroot=YES
pasv_enable=YES
pasv_min_port=10000
pasv_max_port=10100
user_sub_token=\$USER
local_root=/home/\$USER/web/$DOMAIN/public_html
userlist_enable=YES
userlist_file=/etc/vsftpd.userlist
userlist_deny=NO
EOL
    systemctl restart vsftpd
    echo "$HESTIA_USER" >> /etc/vsftpd.userlist

    # Configure Reverse Proxy
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
            ln -s "/etc/nginx/sites-available/$SUBDOMAIN" "/etc/nginx/sites-enabled/"
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
        ln -s "/etc/nginx/sites-available/$SUBDOMAIN" "/etc/nginx/sites-enabled/"
        certbot --nginx -d $SUBDOMAIN --non-interactive --agree-tos -m $EMAIL

        # Validate issued certificate
        CERT_PATH="/etc/letsencrypt/live/$SUBDOMAIN/fullchain.pem"
        if [ -f "$CERT_PATH" ]; then
            echo "Certificate for $SUBDOMAIN is successfully issued and available at $CERT_PATH"
        else
            echo "Error: Certificate for $SUBDOMAIN was not issued. Check Certbot logs for details."
            exit 1
        fi
    done

    # Reload Nginx
    nginx -t && systemctl reload nginx

    # Configure Cloudflare DNS Records
    echo "Configuring DNS records with Cloudflare..."
    for SUBDOMAIN in "${REVERSE_DOMAINS[@]}"; do
        curl -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data '{"type":"A","name":"'$SUBDOMAIN'","content":"$(curl -s ifconfig.me)","ttl":120,"proxied":true}'
    done

    # Setup Automatic Renewal for Certificates
    echo "0 3 * * * certbot renew --quiet && systemctl reload nginx" | crontab -

    echo "Full setup completed."
}

# Parse script options
if [[ "$1" == "--backup" ]]; then
    backup_configurations
elif [[ "$1" == "--install-fail2ban" ]]; then
    install_fail2ban
elif [[ "$1" == "--configure-ssh" ]]; then
    configure_ssh_key
elif [[ "$1" == "--full-setup" ]]; then
    full_setup
else
    echo "Usage: $0 [--backup | --install-fail2ban | --configure-ssh | --full-setup]"
    exit 1
fi

# Final message
echo "Setup script completed with the selected option."
