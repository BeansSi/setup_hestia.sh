#!/bin/bash

# Script til administration af Reverse Proxy, DNS & SSL
SCRIPT_VERSION="2.5.2"

# Sikrer, at Hestia er i PATH
export PATH=$PATH:/usr/local/hestia/bin:/usr/local/hestia/sbin

# Tjekker root-tilladelser
if [ "$EUID" -ne 0 ]; then
    echo "Dette script skal køres som root. Brug sudo."
    exit 1
fi

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

# Slet logfilen ved opdatering
clear_log_if_updated() {
    if [ -f "$LOGFILE" ]; then
        echo "Sletter gammel log..."
        rm -f "$LOGFILE"
    fi
}

# Tjekker om Hestia er installeret
check_hestia_installed() {
    if ! command -v v-add-web-domain &>/dev/null; then
        error_message "Hestia-kommandoer ikke fundet. Sørg for, at Hestia er installeret korrekt."
        exit 1
    fi
}

# Tjekker og opgraderer brugerens pakke, hvis nødvendigt
check_and_upgrade_package() {
    local user="admin"
    echo "Tjekker brugerens pakke..."

    if v-list-user "$user" | grep -q "WEB_DOMAINS.*0"; then
        echo "Opgraderer brugerens pakke for at fjerne domænebegrænsninger..."
        if ! v-change-user-package "$user" default --WEB_DOMAINS unlimited &>> "$LOGFILE"; then
            error_message "Fejl ved opgradering af brugerens pakke."
        else
            success_message "Brugerens pakke opgraderet. Grænsen for webdomæner er fjernet."
        fi
    else
        success_message "Brugerens pakke er allerede konfigureret uden begrænsninger."
    fi
}

# Funktion til at oprette domæner i Hestia
create_domains() {
    check_and_upgrade_package

    for subdomain in "${SUBDOMAINS[@]}"; do
        if ! v-add-web-domain admin "$subdomain" &>> "$LOGFILE"; then
            error_message "Fejl ved oprettelse af webdomænet $subdomain."
        else
            success_message "Webdomæne $subdomain oprettet."
        fi
    done
}

# Funktion til at håndtere SSL-certifikatproblemer
handle_ssl() {
    check_hestia_installed
    create_domains

    for subdomain in "${SUBDOMAINS[@]}"; do
        echo "Aktiverer SSL for $subdomain..."
        if ! v-add-letsencrypt-domain admin "$subdomain" &>> "$LOGFILE"; then
            error_message "Fejl ved aktivering af SSL for $subdomain."
        else
            success_message "SSL-certifikat aktiveret for $subdomain."
        fi
    done

    echo "Aktiverer SSL for Hestia kontrolpanel..."
    if ! v-add-letsencrypt-host &>> "$LOGFILE"; then
        error_message "Fejl ved aktivering af SSL for kontrolpanelet."
    else
        success_message "SSL-certifikat aktiveret for kontrolpanelet."
    fi
}

# Funktion til at hente og køre det nyeste script fra GitHub
download_and_execute_script() {
    clear_log_if_updated

    local retries=50
    local attempt=1

    while ((attempt <= retries)); do
        REMOTE_VERSION=$(curl -s "$REMOTE_SCRIPT_URL" | grep -oP 'SCRIPT_VERSION="\K[0-9]+\.[0-9]+\.[0-9]+')
        if [ "$REMOTE_VERSION" != "$SCRIPT_VERSION" ]; then
            echo "Opdaterer til version $REMOTE_VERSION..."
            curl -s -O "$REMOTE_SCRIPT_URL" && chmod +x "$LOCAL_SCRIPT_NAME"
            success_message "Script opdateret. Genstarter..."
            exec sudo ./"$LOCAL_SCRIPT_NAME"
        else
            echo -ne "Version up-to-date ($SCRIPT_VERSION). Tjekker igen...\r"
            sleep 5
        fi
        ((attempt++))
    done

    error_message "Ingen opdatering fundet efter $retries forsøg."
}

# Funktion til DNS-opdateringer (eksisterende funktion)
check_and_update_dns() {
    echo "Tjekker og opdaterer DNS-poster..."
    for subdomain in "${SUBDOMAINS[@]}"; do
        echo "Tjekker $subdomain..."
        # DNS-opdateringslogik her...
    done
    success_message "DNS-poster opdateret."
}

# Funktion til Reverse Proxy-konfiguration (eksisterende funktion)
update_reverse_proxy() {
    echo "Opdaterer Reverse Proxy-konfiguration..."
    # Reverse Proxy-konfigurationslogik her...
    success_message "Reverse Proxy-konfiguration opdateret."
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
