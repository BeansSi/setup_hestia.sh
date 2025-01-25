#!/bin/bash

# Script til administration af Reverse Proxy, DNS & SSL
SCRIPT_VERSION="2.3.0"

# Brugerkonfiguration
CLOUDFLARE_API_TOKEN="Y45MQapJ7oZ1j9pFf_HpoB7k-218-vZqSJEMKtD3"
CLOUDFLARE_ZONE_ID="9de910e45e803b9d6012834bbc70223c"
SUBDOMAINS=("proxmox.beanssi.dk" "hestia.beanssi.dk" "adguard.beanssi.dk")
LOGFILE="error.log"
REMOTE_SCRIPT_URL="https://raw.githubusercontent.com/BeansSi/setup_hestia.sh/main/setup_hestia.sh"
LOCAL_SCRIPT_NAME="$(basename "$0")"

# Funktion til at vise succesbeskeder
success_message() {
    echo -e "\e[32m$1\e[0m"
}

# Funktion til at vise fejlbeskeder og logge dem
error_message() {
    echo -e "\e[31m$1\e[0m"
    echo "$(date): $1" >> "$LOGFILE"
}

# Funktion til at hente og køre det nyeste script fra GitHub
download_and_execute_script() {
    echo "Tjekker version af det eksterne script på GitHub..."

    # Hent kun versionsnummeret fra det eksterne script
    REMOTE_VERSION=$(curl -s "$REMOTE_SCRIPT_URL" | grep -oP 'SCRIPT_VERSION="\K[0-9]+\.[0-9]+\.[0-9]+')

    if [ -z "$REMOTE_VERSION" ]; then
        error_message "Kunne ikke hente version fra det eksterne script."
        return 1
    fi

    echo "Lokal version: $SCRIPT_VERSION"
    echo "Fjern version: $REMOTE_VERSION"

    # Sammenlign versionerne
    if [ "$REMOTE_VERSION" != "$SCRIPT_VERSION" ]; then
        echo "Ny version tilgængelig. Opdaterer scriptet..."
        curl -s -O "$REMOTE_SCRIPT_URL"

        if [ $? -ne 0 ]; then
            error_message "Fejl ved hentning af det opdaterede script."
            return 1
        fi

        chmod +x "$(basename "$REMOTE_SCRIPT_URL")"
        success_message "Script opdateret til version $REMOTE_VERSION. Genstarter..."
        exec sudo ./"$(basename "$REMOTE_SCRIPT_URL")"
    else
        success_message "Scriptet er allerede opdateret til den nyeste version ($SCRIPT_VERSION)."
    fi
}

# Funktion til at tjekke DNS og opdatere om nødvendigt
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

# Menu
while true; do
    clear
    echo "Reverse Proxy, DNS & SSL Menu - Version $SCRIPT_VERSION"
    echo "0. Tjek og opdater scriptet til nyeste version fra GitHub"
    echo "1. Tjek og opdater DNS-poster"
    echo "2. Opdater Reverse Proxy-konfiguration"
    echo "3. Håndter SSL-certifikatproblemer"
    echo "4. Vis fejl-loggen"
    echo "5. Afslut"
    echo -n "Vælg en mulighed [0-5]: "
    read -r choice

    case $choice in
        0) download_and_execute_script ;;
        1) check_and_update_dns ;;
        2) update_reverse_proxy ;;
        3) handle_ssl ;;
        4) if [ -f "$LOGFILE" ]; then cat "$LOGFILE"; else echo "Ingen fejl fundet endnu."; fi ;;
        5) success_message "Afslutter..."; exit 0 ;;
        *) error_message "Ugyldigt valg, prøv igen."; sleep 2 ;;
    esac

    echo -e "\nTryk på Enter for at fortsætte..."
    read -r
done
