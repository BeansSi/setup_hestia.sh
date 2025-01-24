#!/bin/bash

# Tjek om scriptet køres som root
if [ "$(id -u)" -ne 0 ]; then
    echo "Dette script skal køres som root!"
    exit 1
fi

echo "Starter nulstilling og opsætning af Nginx-konfigurationer..."

# Domæner
DOMAINS=("proxmox.beanssi.dk" "hestia.beanssi.dk" "beanssi.dk")

# Slet gamle konfigurationsfiler
echo "Sletter eksisterende Nginx-konfigurationsfiler..."
for DOMAIN in "${DOMAINS[@]}"; do
    rm -f /etc/nginx/conf.d/$DOMAIN.conf
    rm -f /etc/nginx/conf.d/domains/$DOMAIN.ssl.conf
done

# Opret korrekte Nginx-konfigurationer
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

# Opret valideringsmappe
echo "Opretter mappe til Let's Encrypt valideringsfiler..."
mkdir -p /var/www/letsencrypt/.well-known/acme-challenge/

# Opret testfiler
echo "Opretter testfiler..."
echo "Test for Proxmox" > /var/www/letsencrypt/.well-known/acme-challenge/test_proxmox
echo "Test for Hestia" > /var/www/letsencrypt/.well-known/acme-challenge/test_hestia
echo "Test for Beanssi" > /var/www/letsencrypt/.well-known/acme-challenge/test_beanssi

# Test og genindlæs Nginx
echo "Tester og genindlæser Nginx..."
nginx -t && systemctl reload nginx

# Slutbesked
echo "Nginx-konfigurationer er nulstillet og opsat korrekt!"
echo "Test dine domæner ved at tilgå:"
echo "  http://proxmox.beanssi.dk/.well-known/acme-challenge/test_proxmox"
echo "  http://hestia.beanssi.dk/.well-known/acme-challenge/test_hestia"
echo "  http://beanssi.dk/.well-known/acme-challenge/test_beanssi"

exit 0
