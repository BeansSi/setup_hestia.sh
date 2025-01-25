#!/bin/bash

# Script til administration af Reverse Proxy, DNS & SSL
SCRIPT_VERSION="2.2.2"

# Brugerkonfiguration
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

# Funktion til at hente og køre det nyeste script fra GitHub
download_and_execute_script() {
    echo "Henter den nyeste version af setup_hestia.sh fra GitHub..."
    curl -O https://raw.githubusercontent.com/BeansSi/setup_hestia.sh/main/setup_hestia.sh

    if [ $? -ne 0 ]; then
        error_message "Fejl ved hentning af script fra GitHub."
        return 1
    fi

    chmod +x setup_hestia.sh
    success_message "Script hentet og gjort eksekverbart."
    echo "Genstarter scriptet med den opdaterede version..."

    # Kontroller, om scriptet indeholder nødvendige funktioner
    if ! grep -q "update_reverse_proxy" setup_hestia.sh; then
        error_message "Den nye version af scriptet mangler nødvendige funktioner. Afbryder."
        return 1
    fi

    exec sudo ./setup_hestia.sh
}

# Funktion til at opdatere Reverse Proxy-konfigurationen
update_reverse_proxy() {
    echo "Opdaterer Reverse Proxy-konfiguration for subdomæner..."

    # Sørg for, at mapperne eksisterer
    if [ ! -d /etc/nginx/sites-available ]; then
        mkdir -p /etc/nginx/sites-available || {
            error_message "Kunne ikke oprette /etc/nginx/sites-available."
            return 1
        }
        success_message "Mappen /etc/nginx/sites-available blev oprettet."
    fi

    if [ ! -d /etc/nginx/sites-enabled ]; then
        mkdir -p /etc/nginx/sites-enabled || {
            error_message "Kunne ikke oprette /etc/nginx/sites-enabled."
            return 1
        }
        success_message "Mappen /etc/nginx/sites-enabled blev oprettet."
    fi

    # Sørg for, at Nginx er installeret
    if ! command -v nginx &> /dev/null; then
        error_message "Nginx er ikke installeret. Installerer Nginx..."
        apt update && apt install -y nginx || {
            error_message "Fejl under installation af Nginx."
            return 1
        }
        success_message "Nginx blev installeret."
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
        proxy_pass https://192.168.50.51:8083;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}

server {
    server_name adguard.beanssi.dk;
    location / {
        proxy_pass http://192.168.50.52:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

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
    echo "Reverse Proxy, DNS & SSL Menu - Version $SCRIPT_VERSION"
    echo "0. Hent og kør nyeste setup_hestia.sh fra GitHub"
    echo "1. Tjek og opdater DNS-poster"
    echo "2. Opdater Reverse Proxy-konfiguration"
    echo "3. Aktiver SSL-certifikater"
    echo "4. Vis fejl-loggen"
    echo "5. Afslut"
    echo -n "Vælg en mulighed [0-5]: "
    read -r choice

    case $choice in
        0) download_and_execute_script ;;
        1) check_and_update_dns ;;
        2) update_reverse_proxy ;;
        3) setup_ssl ;;
        4) if [ -f "$LOGFILE" ]; then cat "$LOGFILE"; else echo "Ingen fejl fundet endnu."; fi ;;
        5) success_message "Afslutter..."; exit 0 ;;
        *) error_message "Ugyldigt valg, prøv igen."; sleep 2 ;;
    esac

    echo -e "\nTryk på Enter for at fortsætte..."
    read -r
done
