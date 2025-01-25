#!/bin/bash

# Script til installation og administration af Hestia Control Panel med Cloudflare-integration og reverse proxy
SCRIPT_VERSION="1.0.2"  # Opdater denne version manuelt ved ændringer

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

# Funktion til at oprette eller opdatere DNS-poster via Cloudflare
check_and_update_dns() {
    echo "Tjekker DNS-poster i Cloudflare..."
    for subdomain in "${SUBDOMAINS[@]}"; do
        expected_ip="192.168.50.50"
        if [[ "$subdomain" == "hestia.beanssi.dk" ]]; then
            expected_ip="192.168.50.51"
        elif [[ "$subdomain" == "adguard.beanssi.dk" ]]; then
            expected_ip="192.168.50.52"
        fi

        echo "Tjekker $subdomain..."
        response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records?name=$subdomain" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json")

        current_ip=$(echo "$response" | jq -r '.result[0].content')

        if [[ "$current_ip" == "$expected_ip" ]]; then
            success_message "DNS-posten for $subdomain er korrekt ($current_ip)."
        else
            error_message "DNS for $subdomain er forkert (forventet: $expected_ip, fundet: $current_ip). Opdaterer DNS..."
            record_id=$(echo "$response" | jq -r '.result[0].id')
            if [[ "$record_id" == "null" ]]; then
                # Opretter ny DNS-post
                response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
                -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
                -H "Content-Type: application/json" \
                --data '{
                    "type": "A",
                    "name": "'"$subdomain"'",
                    "content": "'"$expected_ip"'",
                    "ttl": 3600,
                    "proxied": false
                }')

                if echo "$response" | grep -q '"success":true'; then
                    success_message "DNS for $subdomain blev oprettet korrekt."
                else
                    error_message "Fejl ved oprettelse af DNS for $subdomain. Response: $response"
                fi
            else
                # Opdaterer eksisterende DNS-post
                response=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records/$record_id" \
                -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
                -H "Content-Type: application/json" \
                --data '{
                    "type": "A",
                    "name": "'"$subdomain"'",
                    "content": "'"$expected_ip"'",
                    "ttl": 3600,
                    "proxied": false
                }')

                if echo "$response" | grep -q '"success":true'; then
                    success_message "DNS for $subdomain blev opdateret korrekt."
                else
                    error_message "Fejl ved opdatering af DNS for $subdomain. Response: $response"
                fi
            fi
        fi
    done
    echo "DNS-tjek afsluttet."
}

# Funktion til installation eller opdatering af Hestia
install_or_update_hestia() {
    success_message "Starter installation eller opdatering af Hestia..."
    
    # Logger kritisk information
    echo "Hestia installation log - $(date)" >> "$LOGFILE"
    echo "Hostname: $HOSTNAME" >> "$LOGFILE"
    echo "Admin Email: $ADMIN_EMAIL" >> "$LOGFILE"
    echo "Admin Password: $ADMIN_PASSWORD" >> "$LOGFILE"

    # Installerer Hestia Control Panel
    success_message "Installerer Hestia Control Panel..."
    wget https://raw.githubusercontent.com/hestiacp/hestiacp/release/install/hst-install.sh -O hst-install-ubuntu.sh
    if bash hst-install-ubuntu.sh \
        --apache yes \
        --phpfpm yes \
        --multiphp yes \
        --mysql yes \
        --postgresql yes \
        --exim no \
        --dovecot no \
        --clamav no \
        --spamassassin no \
        --iptables yes \
        --fail2ban yes \
        --quota no \
        --named yes \
        --hostname "$HOSTNAME" \
        --email "$ADMIN_EMAIL" \
        --password "$ADMIN_PASSWORD" \
        --interactive no \
        --force; then
        success_message "Hestia blev installeret korrekt."
    else
        error_message "Installation af Hestia mislykkedes."
    fi
}

# Menu
while true; do
    clear
    echo "Hestia Menu - Version $SCRIPT_VERSION"
    echo "1. Tjek og opdater DNS-poster"
    echo "2. Installer eller opdater Hestia"
    echo "3. Vis fejl-loggen"
    echo "4. Afslut"
    echo -n "Vælg en mulighed [1-4]: "
    read -r choice

    case $choice in
        1) check_and_update_dns ;;
        2) install_or_update_hestia ;;
        3) if [ -f "$LOGFILE" ]; then cat "$LOGFILE"; else echo "Ingen fejl fundet endnu."; fi ;;
        4) success_message "Afslutter..."; exit 0 ;;
        *) error_message "Ugyldigt valg, prøv igen."; sleep 2 ;;
    esac

    echo -e "\nTryk på Enter for at fortsætte..."
    read -r
done
