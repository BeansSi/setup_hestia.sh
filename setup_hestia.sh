#!/bin/bash

# Script til administration af Reverse Proxy, DNS & SSL
SCRIPT_VERSION="2.6.1"

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
            error_message "Fejl ved opgradering af brugerens pakke. Tjek loggen for detaljer."
            exit 1
        else
            success_message "Brugerens pakke opgraderet. Grænsen for webdomæner er fjernet."
        fi
    else
        success_message "Brugerens pakke har allerede ingen begrænsninger."
    fi
}

# Opretter en Reverse Proxy-skabelon
create_reverse_proxy_template() {
    echo "Opretter Reverse Proxy-skabelon..."
    local template_path="/usr/local/hestia/data/templates/web/nginx/reverse_proxy.tpl"

    cat <<EOF > "$template_path"
server {
    listen      80;
    server_name %domain_idn% www.%domain_idn%;
    return 301 https://\$host\$request_uri;
}

server {
    listen      443 ssl;
    server_name %domain_idn% www.%domain_idn%;

    ssl_certificate      /etc/ssl/certs/%domain%.crt;
    ssl_certificate_key  /etc/ssl/certs/%domain%.key;

    location / {
        proxy_pass http://%ip%:%port%;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

    if [ -f "$template_path" ]; then
        success_message "Reverse Proxy-skabelon oprettet: $template_path"
    else
        error_message "Kunne ikke oprette Reverse Proxy-skabelon."
        exit 1
    fi
}

# Opretter domæner i Hestia og anvender Reverse Proxy
create_domains() {
    check_and_upgrade_package
    create_reverse_proxy_template

    for subdomain in "${SUBDOMAINS[@]}"; do
        local ip port
        case "$subdomain" in
            "proxmox.beanssi.dk") ip="192.168.50.50"; port="8006" ;;
            "hestia.beanssi.dk") ip="192.168.50.51"; port="8083" ;;
            "adguard.beanssi.dk") ip="192.168.50.52"; port="3000" ;;
        esac

        echo "Opretter domæne $subdomain med Reverse Proxy..."
        if ! v-add-web-domain admin "$subdomain" &>> "$LOGFILE"; then
            error_message "Fejl ved oprettelse af webdomænet $subdomain."
        else
            v-change-web-domain-tpl admin "$subdomain" reverse_proxy &>> "$LOGFILE"
            success_message "Webdomæne $subdomain oprettet med Reverse Proxy."
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
        2) create_domains ;;
        3) handle_ssl ;;
        4) if [ -f "$LOGFILE" ]; then cat "$LOGFILE"; else echo "Ingen fejl fundet endnu."; fi ;;
        5) success_message "Afslutter..."; exit 0 ;;
        *) error_message "Ugyldigt valg, prøv igen."; sleep 2 ;;
    esac

    echo -e "\nTryk på Enter for at fortsætte..."
    read -r
done
