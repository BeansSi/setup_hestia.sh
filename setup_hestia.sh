#!/bin/bash

# Script til administration af Reverse Proxy, DNS & SSL
SCRIPT_VERSION="2.4.1"

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

# Funktion til at oprette domæner i Hestia
create_domains() {
    echo "Opretter webdomæner i Hestia..."
    for subdomain in "${SUBDOMAINS[@]}"; do
        if v-add-web-domain admin "$subdomain" &>> "$LOGFILE"; then
            success_message "Webdomæne $subdomain blev oprettet."
        else
            error_message "Fejl ved oprettelse af webdomænet $subdomain. Tjek loggen."
        fi
    done
}

# Funktion til at håndtere SSL-certifikatproblemer
handle_ssl() {
    echo "Håndterer SSL-certifikatproblemer og aktiverer Let's Encrypt..."

    # Opret domæner, hvis de mangler
    create_domains

    for subdomain in "${SUBDOMAINS[@]}"; do
        echo "Kontrollerer SSL for $subdomain..."

        ufw allow 80/tcp &> /dev/null && success_message "Port 80 er åben."
        ufw allow 443/tcp &> /dev/null && success_message "Port 443 er åben."

        if v-add-letsencrypt-domain admin "$subdomain" &>> "$LOGFILE"; then
            success_message "Let's Encrypt-certifikat aktiveret for $subdomain."
        else
            error_message "Fejl ved aktivering af Let's Encrypt for $subdomain. Se detaljer i loggen."
        fi
    done

    echo "Aktiverer Let's Encrypt for Hestia kontrolpanel..."
    if v-add-letsencrypt-host &>> "$LOGFILE"; then
        success_message "Let's Encrypt-certifikat aktiveret for kontrolpanelet."
    else
        error_message "Fejl ved aktivering af Let's Encrypt for kontrolpanelet. Se detaljer i loggen."
    fi
}

# Funktion til at hente og køre det nyeste script fra GitHub
download_and_execute_script() {
    local retries=5
    local retry_delay=30
    local attempt=1

    echo "Tjekker version af det eksterne script på GitHub..."

    while ((attempt <= retries)); do
        echo "Forsøg $attempt af $retries..."

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
            echo "Ingen opdatering fundet. Venter $retry_delay sekunder og prøver igen..."
            sleep $retry_delay
            ((attempt++))
        fi
    done

    error_message "Ingen nye opdateringer fundet efter $retries forsøg."
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
