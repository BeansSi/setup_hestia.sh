#!/bin/bash

log_file="/var/log/setup_hestia.log"

# Funktion til logning
log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $level: $message"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $level: $message" >> "$log_file"
}

# Funktion til at kontrollere og genstarte en tjeneste
check_service() {
    local service="$1"
    log "INFO" "Kontrollerer status for $service..."
    if ! systemctl is-active --quiet "$service"; then
        log "ERROR" "$service kører ikke. Forsøger at genstarte..."
        systemctl restart "$service"
        if ! systemctl is-active --quiet "$service"; then
            log "CRITICAL" "Kunne ikke genstarte $service. Kontrollér manuelt."
            systemctl status "$service" >> "$log_file"
            exit 1
        else
            log "SUCCESS" "$service genstartet korrekt."
        fi
    else
        log "INFO" "$service kører korrekt."
    fi
}

# Funktion til at nulstille Nginx-konfigurationer
reset_nginx_config() {
    log "INFO" "Sletter eksisterende Nginx-konfigurationsfiler..."
    local files=(
        "/etc/nginx/conf.d/proxmox.beanssi.dk.conf"
        "/etc/nginx/conf.d/hestia.beanssi.dk.conf"
        "/etc/nginx/conf.d/beanssi.dk.conf"
    )
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log "INFO" "✔ Fil slettet: $file"
        else
            log "INFO" "ℹ Fil findes ikke: $file"
        fi
    done
}

# Funktion til at oprette Nginx-konfigurationer
create_nginx_config() {
    log "INFO" "Opretter nye Nginx-konfigurationsfiler..."
    cat > /etc/nginx/conf.d/proxmox.beanssi.dk.conf <<EOF
server {
    listen 80;
    server_name proxmox.beanssi.dk;
    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }
    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF
    log "INFO" "✔ Konfigurationsfil oprettet: /etc/nginx/conf.d/proxmox.beanssi.dk.conf"

    cat > /etc/nginx/conf.d/hestia.beanssi.dk.conf <<EOF
server {
    listen 80;
    server_name hestia.beanssi.dk;
    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }
    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF
    log "INFO" "✔ Konfigurationsfil oprettet: /etc/nginx/conf.d/hestia.beanssi.dk.conf"

    cat > /etc/nginx/conf.d/beanssi.dk.conf <<EOF
server {
    listen 80;
    server_name beanssi.dk www.beanssi.dk;
    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }
    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF
    log "INFO" "✔ Konfigurationsfil oprettet: /etc/nginx/conf.d/beanssi.dk.conf"
}

# Funktion til at genindlæse Nginx
reload_nginx() {
    log "INFO" "Genindlæser Nginx..."
    if nginx -t; then
        systemctl reload nginx
        log "SUCCESS" "✔ Nginx genindlæst."
    else
        log "CRITICAL" "Nginx-konfigurationen er ugyldig. Kontrollér fejlene i loggen."
        exit 1
    fi
}

# Funktion til at generere selvsignerede certifikater
generate_certificates() {
    local domains=("proxmox.beanssi.dk" "hestia.beanssi.dk" "beanssi.dk")
    for domain in "${domains[@]}"; do
        local cert_path="/etc/letsencrypt/live/$domain"
        if [[ ! -f "$cert_path/fullchain.pem" ]]; then
            log "INFO" "Genererer selvsigneret certifikat for $domain..."
            mkdir -p "$cert_path"
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout "$cert_path/privkey.pem" \
                -out "$cert_path/fullchain.pem" \
                -subj "/CN=$domain"
            log "SUCCESS" "✔ Selvsigneret certifikat genereret for $domain."
        else
            log "INFO" "ℹ Certifikat for $domain findes allerede."
        fi
    done
}

# Funktion til at teste URL'er
test_urls() {
    local urls=(
        "http://proxmox.beanssi.dk/.well-known/acme-challenge/test_proxmox"
        "http://hestia.beanssi.dk/.well-known/acme-challenge/test_hestia"
        "http://beanssi.dk/.well-known/acme-challenge/test_beanssi"
    )
    local failed=0
    for url in "${urls[@]}"; do
        log "INFO" "Tester URL: $url"
        local response
        response=$(curl -s "$url")
        if [[ "$response" == "Test" ]]; then
            log "SUCCESS" "✔ URL-test bestået: $url"
        else
            log "ERROR" "❌ URL-test fejlede: $url. Forventet 'Test', men fik: '$response'."
            ((failed++))
        fi
    done
    if ((failed > 0)); then
        log "CRITICAL" "En eller flere URL-tests fejlede. Kontrollér Nginx-konfigurationen."
        exit 1
    fi
}

# Hovedfunktion
main() {
    log "INFO" "Starter opsætning..."
    check_service "nginx"
    check_service "hestia"
    reset_nginx_config
    create_nginx_config
    reload_nginx
    generate_certificates
    test_urls
    log "SUCCESS" "Opsætningen er fuldført!"
}

main
