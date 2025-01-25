#!/bin/bash

# Script til administration af Hestia Control Panel med Cloudflare-integration og reverse proxy
SCRIPT_VERSION="1.0.4"  # Opdateret version

# Tjekker, om scriptet køres som root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "\e[31mDette script skal køres som root. Brug sudo.\e[0m"
    exit 1
fi

# Brugerkonfiguration
HOSTNAME="hestia.beanssi.dk"
ADMIN_EMAIL="beans@beanssi.dk"
ADMIN_PASSWORD="minmis123"
CLOUDFLARE_EMAIL="beanssiii@gmail.com"
CLOUDFLARE_API_TOKEN="Y45MQapJ7oZ1j9pFf_HpoB7k-218-vZqSJEMKtD3"
CLOUDFLARE_ZONE_ID="9de910e45e803b9d6012834bbc70223c"
SUBDOMAINS=("proxmox.beanssi.dk" "hestia.beanssi.dk" "adguard.beanssi.dk")
LOGFILE="error.log"

# Funktion til at vise succesbeskeder
success_message() {
    echo -e "\e[32m$1\e[0m"
}

# Funktion til at vise fejlbeskeder og logge dem
error_message() {
    echo -e "\e[31m$1\e[0m"
    echo "$(date): $1" >> "$LOGFILE"
}

# Funktion til at opdatere Reverse Proxy-konfigurationen
update_reverse_proxy() {
    echo "Opdaterer Reverse Proxy-konfiguration for subdomæner..."

    # Sørg for, at mapperne eksisterer
    if [ ! -d /etc/nginx/sites-available ]; then
        mkdir -p /etc/nginx/sites-available
        if [ $? -eq 0 ]; then
            success_message "Mappen /etc/nginx/sites-available blev oprettet."
        else
            error_message "Kunne ikke oprette /etc/nginx/sites-available."
            return 1
        fi
    fi

    if [ ! -d /etc/nginx/sites-enabled ]; then
        mkdir -p /etc/nginx/sites-enabled
        if [ $? -eq 0 ]; then
            success_message "Mappen /etc/nginx/sites-enabled blev oprettet."
        else
            error_message "Kunne ikke oprette /etc/nginx/sites-enabled."
            return 1
        fi
    fi

    # Sørg for, at Nginx er installeret
    if ! command -v nginx &> /dev/null; then
        error_message "Nginx er ikke installeret. Installerer Nginx..."
        apt update && apt install -y nginx
        if [ $? -eq 0 ]; then
            success_message "Nginx blev installeret."
        else
            error_message "Fejl under installation af Nginx."
            return 1
        fi
    fi

    # Opretter eller opdaterer reverse proxy-konfiguration
    cat <<EOF > /etc/nginx/sites-available/reverse_proxy.conf
server {
    server_name proxmox.beanssi.dk;
    location / {
        proxy_pass https://192.168.50.50:8006;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_ssl_verify off;
    }
}

server {
    server_name hestia.beanssi.dk;
    location / {
        proxy_pass https://127.0.0.1:8083;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}

server {
    server_name adguard.beanssi.dk;
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

    # Opretter symbolsk link
    ln -sf /etc/nginx/sites-available/reverse_proxy.conf /etc/nginx/sites-enabled/reverse_proxy.conf

    # Genindlæser Nginx
    if systemctl reload nginx; then
        success_message "Reverse Proxy-konfiguration opdateret og Nginx genindlæst."
    else
        error_message "Fejl ved genindlæsning af Nginx. Tjek konfigurationen manuelt."
    fi
}

# Menu
while true; do
    clear
    echo "Hestia Menu - Version $SCRIPT_VERSION"
    echo "1. Tjek og opdater DNS-poster"
    echo "2. Opdater Reverse Proxy-konfiguration"
    echo "3. Vis fejl-loggen"
    echo "4. Afslut"
    echo -n "Vælg en mulighed [1-4]: "
    read -r choice

    case $choice in
        1) check_and_update_dns ;;
        2) update_reverse_proxy ;;
        3) if [ -f "$LOGFILE" ]; then cat "$LOGFILE"; else echo "Ingen fejl fundet endnu."; fi ;;
        4) success_message "Afslutter..."; exit 0 ;;
        *) error_message "Ugyldigt valg, prøv igen."; sleep 2 ;;
    esac

    echo -e "\nTryk på Enter for at fortsætte..."
    read -r
done
