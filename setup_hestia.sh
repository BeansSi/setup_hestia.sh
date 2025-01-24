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
            log "CRITICAL" "Kunne ikke genstarte $service. Kontrollér manuelt. Her er status:"
            systemctl status "$service" >> "$log_file"
            journalctl -u "$service" >> "$log_file"
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
        nginx -t >> "$log_file"
        exit 1
    fi
}

# Funktion til at fejlsøge hestia.service
troubleshoot_hestia() {
    log "INFO" "Fejlsøger hestia.service..."
    journalctl -u hestia.service -n 50 >> "$log_file"
    log "INFO" "Forsøger at stoppe andre tjenester, der bruger porte, som Hestia kræver."
    for port in 8083 8084; do
        log "INFO" "Tjekker port $port..."
        fuser -k "$port"/tcp
    done
    log "INFO" "Forsøger at genstarte hestia..."
    systemctl restart hestia
    if ! systemctl is-active --quiet hestia; then
        log "CRITICAL" "Kunne stadig ikke starte hestia. Kontrollér manuelt."
        exit 1
    else
        log "SUCCESS" "hestia genstartet korrekt."
    fi
}

# Hovedfunktion
main() {
    log "INFO" "Starter opsætning..."
    check_service "nginx"
    if ! check_service "hestia"; then
        troubleshoot_hestia
    fi
    reset_nginx_config
    create_nginx_config
    reload_nginx
    log "SUCCESS" "Opsætningen er fuldført!"
}

main
