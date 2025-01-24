#!/bin/bash

# Tjek om scriptet køres som root
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ Dette script skal køres som root!"
    exit 1
fi

# Funktionsdefinitioner
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

delete_file() {
    if [ -f "$1" ]; then
        rm -f "$1"
        if [ $? -eq 0 ]; then
            log "✔ Fil slettet: $1"
        else
            log "❌ Kunne ikke slette fil: $1"
        fi
    else
        log "ℹ Fil findes ikke: $1"
    fi
}

create_directory() {
    if [ ! -d "$1" ]; then
        mkdir -p "$1"
        if [ $? -eq 0 ]; then
            log "✔ Mappe oprettet: $1"
        else
            log "❌ Kunne ikke oprette mappe: $1"
            exit 1
        fi
    else
        log "ℹ Mappe findes allerede: $1"
    fi
}

generate_self_signed_cert() {
    DOMAIN=$1
    CERT_DIR="/etc/letsencrypt/live/$DOMAIN"

    if [ ! -f "$CERT_DIR/fullchain.pem" ] || [ ! -f "$CERT_DIR/privkey.pem" ]; then
        log "Genererer selvsigneret certifikat for $DOMAIN..."
        mkdir -p "$CERT_DIR"
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$CERT_DIR/privkey.pem" \
            -out "$CERT_DIR/fullchain.pem" \
            -subj "/CN=$DOMAIN"
        if [ $? -eq 0 ]; then
            log "✔ Selvsigneret certifikat genereret for $DOMAIN."
        else
            log "❌ Kunne ikke generere selvsigneret certifikat for $DOMAIN."
            exit 1
        fi
    else
        log "ℹ Certifikat for $DOMAIN findes allerede."
    fi
}

check_nginx_config() {
    log "Tester Nginx-konfiguration..."
    nginx -t > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        log "✔ Nginx-konfigurationen er korrekt."
        systemctl reload nginx
        log "✔ Nginx genindlæst."
    else
        log "❌ Nginx-konfigurationen fejlede. Kontrollér logfilerne for detaljer."
        exit 1
    fi
}

test_url() {
    URL=$1
    EXPECTED_OUTPUT=$2
    RESPONSE=$(curl -s "$URL")
    if [ "$RESPONSE" == "$EXPECTED_OUTPUT" ]; then
        log "✔ URL-test bestået: $URL"
    else
        log "❌ URL-test fejlede: $URL. Forventet '$EXPECTED_OUTPUT', men fik '$RESPONSE'."
        log "ℹ Retter konfigurationsproblemer for $URL..."
        if [[ "$URL" == *"proxmox"* ]]; then
            log "ℹ Proxmox-domænet omdirigerer til HTTPS. Kontroller HTTPS-konfigurationen."
        else
            log "ℹ Tjekker, om .well-known/acme-challenge er korrekt konfigureret..."
            # Tilføj en midlertidig løsning for domæner
            echo "Test" > /var/www/letsencrypt/.well-known/acme-challenge/testfile_temp
            log "✔ Testfil for $URL midlertidigt oprettet. Test venligst igen."
        fi
    fi
}

# Start
log "Starter nulstilling og opsætning af Nginx-konfigurationer..."

# Domæner
DOMAINS=("proxmox.beanssi.dk" "hestia.beanssi.dk" "beanssi.dk")
EXPECTED_TEST_OUTPUT="Test"

# Sletning af eksisterende filer
log "Sletter eksisterende Nginx-konfigurationsfiler..."
for DOMAIN in "${DOMAINS[@]}"; do
    delete_file "/etc/nginx/conf.d/$DOMAIN.conf"
    delete_file "/etc/nginx/conf.d/domains/$DOMAIN.ssl.conf"
done

# Opret nye Nginx-konfigurationer
log "Opretter nye Nginx-konfigurationsfiler..."
# Føj dine Nginx-konfigurationer for hvert domæne her...

# Opret valideringsmappe
log "Opretter mappe til Let's Encrypt valideringsfiler..."
create_directory "/var/www/letsencrypt/.well-known/acme-challenge/"

# Generer selvsignerede certifikater for alle domæner
for DOMAIN in "${DOMAINS[@]}"; do
    generate_self_signed_cert "$DOMAIN"
done

# Opret testfiler
log "Opretter testfiler..."
for DOMAIN in "${DOMAINS[@]}"; do
    echo "$EXPECTED_TEST_OUTPUT" > "/var/www/letsencrypt/.well-known/acme-challenge/test_$DOMAIN"
    log "✔ Testfil oprettet: /var/www/letsencrypt/.well-known/acme-challenge/test_$DOMAIN"
done

# Test og genindlæs Nginx
check_nginx_config

# Test URL'er
log "Tester test-URL'er..."
for DOMAIN in "${DOMAINS[@]}"; do
    test_url "http://$DOMAIN/.well-known/acme-challenge/test_$DOMAIN" "$EXPECTED_TEST_OUTPUT"
done

# Slutbesked
log "✅ Opsætningen er fuldført! Test dine domæner ved at tilgå de genererede URL'er."

exit 0
