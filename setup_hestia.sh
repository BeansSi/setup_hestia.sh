#!/bin/bash

# Tjek om scriptet køres som root
if [ "$(id -u)" -ne 0 ]; then
    echo "Dette script skal køres som root!"
    exit 1
fi

echo "Starter opsætning for hestia.beanssi.dk..."

# Fjern gamle og konflikterende konfigurationsfiler
echo "Fjerner gamle konfigurationsfiler..."
rm -f /etc/nginx/conf.d/hestia.beanssi.dk.conf
rm -f /etc/nginx/conf.d/domains/hestia.beanssi.dk.ssl.conf
rm -f /etc/nginx/conf.d/letsencrypt.conf

# Opret ny konfigurationsfil for hestia.beanssi.dk
echo "Opretter ny konfigurationsfil..."
cat <<EOL > /etc/nginx/conf.d/hestia.beanssi.dk.conf
server {
    listen 80;
    server_name hestia.beanssi.dk;

    # Let's Encrypt HTTP validation
    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
        allow all;
    }

    # Proxy til Hestia Control Panel
    location / {
        proxy_pass https://127.0.0.1:8083;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto http;
    }
}
EOL

# Opret mappen til Let's Encrypt-validering
echo "Sikrer at Let's Encrypt valideringsmappe findes..."
mkdir -p /var/www/letsencrypt/.well-known/acme-challenge/

# Opret testfil til validering
echo "Opretter testfil..."
echo "Test" > /var/www/letsencrypt/.well-known/acme-challenge/testfile

# Test og genindlæs Nginx-konfiguration
echo "Tester og genindlæser Nginx..."
nginx -t && systemctl reload nginx

# Slutbesked
echo "Opsætningen er fuldført! Test filen ved at tilgå:"
echo "http://hestia.beanssi.dk/.well-known/acme-challenge/testfile"

exit 0
