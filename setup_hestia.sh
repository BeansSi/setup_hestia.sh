#!/bin/bash

log_file="/var/log/setup_hestia.log"

# Logging funktion
log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $level: $message" | tee -a "$log_file"
}

# Tjek status for en service
check_service() {
    local service="$1"
    log "INFO" "Kontrollerer status for $service..."
    if ! systemctl is-active --quiet "$service"; then
        log "ERROR" "$service kører ikke. Forsøger at genstarte..."
        systemctl restart "$service"
        if systemctl is-active --quiet "$service"; then
            log "SUCCESS" "$service genstartet korrekt."
        else
            log "CRITICAL" "Kunne ikke genstarte $service. Kontrollér manuelt."
            journalctl -u "$service" | tail -n 20 >> "$log_file"
            exit 1
        fi
    else
        log "INFO" "$service kører korrekt."
    fi
}

# Fjern Nginx-konfigurationsfiler
reset_nginx_config() {
    log "INFO" "Sletter eksisterende Nginx-konfigurationsfiler..."
    rm -f /etc/nginx/conf.d/proxmox.beanssi.dk.conf
    rm -f /etc/nginx/conf.d/hestia.beanssi.dk.conf
    rm -f /etc/nginx/conf.d/beanssi.dk.conf
    log "SUCCESS" "Eksisterende Nginx-konfigurationsfiler slettet."
}

# Genskab Nginx-konfiguration
create_nginx_config() {
    log "INFO" "Genskaber Nginx-konfigurationsfiler..."
    cat <<EOF > /etc/nginx/conf.d/proxmox.beanssi.dk.conf
server {
    listen 80;
    server_name proxmox.beanssi.dk;
    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }
}
EOF

    cat <<EOF > /etc/nginx/conf.d/hestia.beanssi.dk.conf
server {
    listen 80;
    server_name hestia.beanssi.dk;
    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }
}
EOF

    cat <<EOF > /etc/nginx/conf.d/beanssi.dk.conf
server {
    listen 80;
    server_name beanssi.dk;
    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }
}
EOF
    log "SUCCESS" "Nginx-konfigurationsfiler genskabt."
}

# Test og genindlæs Nginx
reload_nginx() {
    log "INFO" "Tester og genindlæser Nginx..."
    if nginx -t; then
        systemctl reload nginx
        log "SUCCESS" "Nginx genindlæst."
    else
        log "CRITICAL" "Nginx-konfiguration mislykkedes. Kontrollér fejl."
        nginx -t 2>&1 | tee -a "$log_file"
        exit 1
    fi
}

# Generer Let's Encrypt-certifikater
generate_certificates() {
    for domain in proxmox.beanssi.dk hestia.beanssi.dk beanssi.dk; do
        log "INFO" "Forsøger at generere certifikat for $domain..."
        if certbot certonly --nginx -d "$domain" --non-interactive --agree-tos -m "admin@$domain"; then
            log "SUCCESS" "Certifikat genereret for $domain."
        else
            log "ERROR" "Kunne ikke generere certifikat for $domain. Kontrollér manuelt."
            certbot renew --dry-run | tee -a "$log_file"
        fi
    done
}

# Script eksekvering
log "INFO" "Starter opsætning..."
check_service "nginx"
check_service "hestia"
reset_nginx_config
create_nginx_config
reload_nginx
generate_certificates
log "INFO" "Opsætningen er fuldført!"
