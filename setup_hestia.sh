#!/bin/bash

# Script til installation og administration af Hestia Control Panel med Cloudflare-integration

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
LOGFILE="hestia_credentials.log"

# Funktion til at vise succesbeskeder
success_message() {
    echo -e "\e[32m$1\e[0m"
}

# Funktion til at vise fejlbeskeder
error_message() {
    echo -e "\e[31m$1\e[0m"
}

# Funktion til at oprette DNS-poster via Cloudflare
create_cloudflare_dns() {
    success_message "Opretter DNS-poster i Cloudflare..."
    for subdomain in "${SUBDOMAINS[@]}"; do
        echo "Opretter A-record for $subdomain..."
        response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data '{
            "type": "A",
            "name": "'"$subdomain"'",
            "content": "192.168.50.50",
            "ttl": 3600,
            "proxied": true
        }')

        if echo "$response" | grep -q '"success":true'; then
            success_message "DNS-posten for $subdomain blev oprettet."
        else
            error_message "Fejl ved oprettelse af DNS-posten for $subdomain."
        fi
    done
}

# Funktion til installation eller opdatering af Hestia
install_or_update_hestia() {
    success_message "Starter installation eller opdatering af Hestia..."
    
    # Logger kritisk information
    echo "Hestia installation log - $(date)" > "$LOGFILE"
    echo "Hostname: $HOSTNAME" >> "$LOGFILE"
    echo "Admin Email: $ADMIN_EMAIL" >> "$LOGFILE"
    echo "Admin Password: $ADMIN_PASSWORD" >> "$LOGFILE"

    # Opdaterer systemet
    success_message "Opdaterer systemet..."
    if apt update -y && apt upgrade -y; then
        success_message "Systemopdatering gennemført."
    else
        error_message "Systemopdatering mislykkedes."
        return
    fi

    # Installerer nødvendige pakker
    success_message "Installerer nødvendige pakker..."
    if DEBIAN_FRONTEND=noninteractive apt install -y curl wget software-properties-common apt-transport-https gnupg jq; then
        success_message "Pakker blev installeret."
    else
        error_message "Installation af nødvendige pakker mislykkedes."
        return
    fi

    # Tilføjer Hestia repository og nøgle
    success_message "Tilføjer Hestia repository..."
    wget -qO - https://apt.hestiacp.com/pubkey.gpg | apt-key add -
    echo "deb https://apt.hestiacp.com/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/hestia.list
    apt update -y

    # Installerer Hestia Control Panel
    success_message "Installerer Hestia Control Panel..."
    wget https://raw.githubusercontent.com/hestiacp/hestiacp/release/install/hst-install.sh -O hst-install.sh
    if bash hst-install.sh --force --yes --nginx yes --apache yes --phpfpm yes --multiphp yes --mysql yes --postgresql yes --exim no --dovecot no --clamav no --spamassassin no --iptables yes --fail2ban yes --quota no --dns yes --hostname "$HOSTNAME" --email "$ADMIN_EMAIL" --password "$ADMIN_PASSWORD"; then
        success_message "Hestia blev installeret korrekt."
    else
        error_message "Installation af Hestia mislykkedes."
        return
    fi

    # Aktiverer SSL med Let's Encrypt
    success_message "Aktiverer Let's Encrypt SSL-certifikater..."
    if hestia v-add-letsencrypt-host; then
        success_message "Let's Encrypt-certifikater blev aktiveret."
    else
        error_message "Fejl ved aktivering af Let's Encrypt-certifikater."
    fi
}

# Menu
while true; do
    clear
    echo "Hestia Menu"
    echo "1. Opret DNS-poster i Cloudflare"
    echo "2. Installer eller opdater Hestia"
    echo "3. Vis loggen"
    echo "4. Afslut"
    echo -n "Vælg en mulighed [1-4]: "
    read -r choice

    case $choice in
        1) create_cloudflare_dns ;;
        2) install_or_update_hestia ;;
        3) if [ -f "$LOGFILE" ]; then cat "$LOGFILE"; else error_message "Ingen logfil fundet."; fi ;;
        4) success_message "Afslutter..."; exit 0 ;;
        *) error_message "Ugyldigt valg, prøv igen."; sleep 2 ;;
    esac

    echo -e "\nTryk på Enter for at fortsætte..."
    read -r
done
