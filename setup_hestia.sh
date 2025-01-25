#!/bin/bash

# Script til administration af Reverse Proxy og DNS-opdatering
SCRIPT_VERSION="2.0.3"

# Aktiverer debug mode (echo alt hvad der sker)
set -x

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

# Funktion til at opdatere DNS-poster via Cloudflare
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
    echo "Reverse Proxy & DNS Menu - Version $SCRIPT_VERSION"
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
