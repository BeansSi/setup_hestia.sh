#!/bin/bash

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

check_and_fix_http() {
    DOMAIN=$1
    CONFIG_PATH="/etc/nginx/conf.d/$DOMAIN.conf"

    # Midlertidig HTTP-konfiguration uden HTTPS
    cat > "$CONFIG_PATH" <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    root /var/www/letsencrypt/;
    location /.well-known/acme-challenge/ {
        allow all;
        autoindex on;
    }
}
EOF

    log "✔ Midlertidig HTTP-konfiguration tilføjet for $DOMAIN."

    # Genindlæs Nginx og test
    nginx -t > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        systemctl reload nginx
        log "✔ Nginx genindlæst med midlertidig HTTP-konfiguration for $DOMAIN."
    else
        log "❌ Nginx-konfigurationsfejl for $DOMAIN. Kontrollér manuelt."
        exit 1
    fi
}

test_url() {
    URL=$1
    EXPECTED_OUTPUT=$2
    DOMAIN=$(echo $URL | awk -F/ '{print $3}')
    RESPONSE=$(curl -s "$URL")
    if [ "$RESPONSE" == "$EXPECTED_OUTPUT" ]; then
        log "✔ URL-test bestået: $URL"
    else
        log "❌ URL-test fejlede: $URL. Forventet '$EXPECTED_OUTPUT', men fik '$RESPONSE'."
        log "➡ Retter fejl for $DOMAIN..."
        check_and_fix_http "$DOMAIN"
        # Test igen efter rettelse
        RESPONSE=$(curl -s "$URL")
        if [ "$RESPONSE" == "$EXPECTED_OUTPUT" ]; then
            log "✔ URL-test bestået efter rettelse: $URL"
        else
            log "❌ URL-test fejlede stadig: $URL. Kontrollér manuelt."
        fi
    fi
}

# Start
log "Starter nulstilling og opsætning af Nginx-konfigurationer..."

# Domæner
DOMAINS=("proxmox.beanssi.dk" "hestia.beanssi.dk" "beanssi.dk")
EXPECTED_TEST_OUTPUT="Test"

# Tester og retter URL'er
log "Tester test-URL'er..."
for DOMAIN in "${DOMAINS[@]}"; do
    TEST_URL="http://$DOMAIN/.well-known/acme-challenge/test_$DOMAIN"
    test_url "$TEST_URL" "$EXPECTED_TEST_OUTPUT"
done

# Slutbesked
log "✅ Opsætningen er fuldført! Test dine domæner igen, og prøv Let's Encrypt-certifikater."
exit 0
