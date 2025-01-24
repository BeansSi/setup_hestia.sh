#!/bin/bash

# Tjek om scriptet køres som root
if [ "$(id -u)" -ne 0 ]; then
    echo "Dette script skal køres som root!"
    exit 1
fi

# Funktionsdefinitioner
function delete_file() {
    if [ -f "$1" ]; then
        rm -f "$1"
        if [ $? -eq 0 ]; then
            echo "✔ Fil slettet: $1"
        else
            echo "❌ Kunne ikke slette fil: $1"
        fi
    else
        echo "ℹ Fil findes ikke: $1"
    fi
}

function delete_directory() {
    if [ -d "$1" ]; then
        rm -rf "$1"
        if [ $? -eq 0 ]; then
            echo "✔ Mappe slettet: $1"
        else
            echo "❌ Kunne ikke slette mappe: $1"
        fi
    else
        echo "ℹ Mappe findes ikke: $1"
    fi
}

function create_directory() {
    if [ ! -d "$1" ]; then
        mkdir -p "$1"
        if [ $? -eq 0 ]; then
            echo "✔ Mappe oprettet: $1"
        else
            echo "❌ Kunne ikke oprette mappe: $1"
        fi
    else
        echo "ℹ Mappe findes allerede: $1"
    fi
}

function check_nginx_config() {
    nginx -t > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "✔ Nginx-konfigurationen er korrekt."
        systemctl reload nginx
        echo "✔ Nginx genindlæst."
    else
        echo "❌ Nginx-konfigurationen fejlede. Kontrollér logfilerne for detaljer."
        exit 1
    fi
}

# Start
echo "Starter nulstilling og opsætning af Nginx-konfigurationer..."

# Domæner
DOMAINS=("proxmox.beanssi.dk" "hestia.beanssi.dk" "beanssi.dk")

# Sletning af eksisterende filer
echo "Sletter eksisterende Nginx-konfigurationsfiler..."
for DOMAIN in "${DOMAINS[@]}"; do
    delete_file "/etc/nginx/conf.d/$DOMAIN.conf"
    delete_file "/etc/nginx/conf.d/domains/$DOMAIN.ssl.conf"
done

# Opret nye Nginx-konfigurationer
echo "Opretter nye Nginx-konfigurationsfiler..."

# Proxmox konfiguration
cat <<EOL > /etc/nginx/conf.d/proxmox.beanssi.dk.conf
server {
    listen 80;
    server_name proxmox.beanssi.dk;

    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name proxmox.beanssi.dk;

    ssl_certificate /etc/letsencrypt/live/proxmox.beanssi.dk/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/proxmox.beanssi.dk/privkey.pem;

    location / {
        proxy_pass https://127.0.0.1:8006;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
EOL
echo "✔ Konfigurationsfil oprettet: /etc/nginx/conf.d/proxmox.beanssi.dk.conf"

# Hestia konfiguration
cat <<EOL > /etc/nginx/conf.d/hestia.beanssi.dk.conf
server {
    listen 80;
    server_name hestia.beanssi.dk;

    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
        allow all;
    }

    location / {
        proxy_pass https://127.0.0.1:8083;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
EOL
echo "✔ Konfigurationsfil oprettet: /etc/nginx/conf.d/hestia.beanssi.dk.conf"

# Beanssi konfiguration
cat <<EOL > /etc/nginx/conf.d/beanssi.dk.conf
server {
    listen 80;
    server_name beanssi.dk www.beanssi.dk;

    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
        allow all;
    }

    location / {
        root /home/beans/web/beanssi.dk/public_html;
        index index.html index.htm;
    }
}
EOL
echo "✔ Konfigurationsfil oprettet: /etc/nginx/conf.d/beanssi.dk.conf"

# Opret valideringsmappe
echo "Opretter mappe til Let's Encrypt valideringsfiler..."
create_directory "/var/www/letsencrypt/.well-known/acme-challenge/"

# Opret testfiler
echo "Opretter testfiler..."
echo "Test for Proxmox" > /var/www/letsencrypt/.well-known/acme-challenge/test_proxmox
echo "Test for Hestia" > /var/www/letsencrypt/.well-known/acme-challenge/test_hestia
echo "Test for Beanssi" > /var/www/letsencrypt/.well-known/acme-challenge/test_beanssi
echo "✔ Testfiler oprettet."

# Test og genindlæs Nginx
echo "Tester og genindlæser Nginx..."
check_nginx_config

# Slutbesked
echo "✅ Opsætningen er fuldført! Test dine domæner ved at tilgå følgende URL'er:"
echo "  http://proxmox.beanssi.dk/.well-known/acme-challenge/test_proxmox"
echo "  http://hestia.beanssi.dk/.well-known/acme-challenge/test_hestia"
echo "  http://beanssi.dk/.well-known/acme-challenge/test_beanssi"

exit 0
