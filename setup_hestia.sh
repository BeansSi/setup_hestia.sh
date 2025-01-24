#!/bin/bash

log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $level: $message"
}

check_service_status() {
    local service="$1"
    log "INFO" "Kontrollerer status for $service..."
    if ! systemctl is-active --quiet "$service"; then
        log "ERROR" "$service er ikke aktiv. Forsøger at genstarte..."
        systemctl restart "$service"
        if systemctl is-active --quiet "$service"; then
            log "SUCCESS" "$service genstartet korrekt."
        else
            log "CRITICAL" "Kunne ikke genstarte $service. Kontrollér manuelt."
        fi
    else
        log "INFO" "$service kører korrekt."
    fi
}

fix_port_conflict() {
    local port="$1"
    log "INFO" "Kontrollerer, om port $port allerede er i brug..."
    if lsof -i :$port | grep LISTEN; then
        log "ERROR" "Port $port er allerede i brug. Dræber processer..."
        fuser -k $port/tcp
        log "SUCCESS" "Port $port frigivet."
    else
        log "INFO" "Port $port er ledig."
    fi
}

setup_nginx() {
    log "INFO" "Nulstilling og opsætning af Nginx-konfigurationer..."
    # Slet eksisterende filer
    for domain in proxmox.beanssi.dk hestia.beanssi.dk beanssi.dk; do
        conf_path="/etc/nginx/conf.d/$domain.conf"
        if [ -f "$conf_path" ]; then
            rm "$conf_path"
            log "SUCCESS" "Fil slettet: $conf_path"
        else
            log "INFO" "Fil findes ikke: $conf_path"
        fi
    done

    # Opret konfigurationsfiler
    cat <<EOF > /etc/nginx/conf.d/proxmox.beanssi.dk.conf
server {
    listen 80;
    server_name proxmox.beanssi.dk;

    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }
}
EOF

    log "SUCCESS" "Nginx-konfigurationsfiler oprettet."

    # Genindlæs Nginx
    log "INFO" "Genindlæser Nginx..."
    if nginx -t && systemctl reload nginx; then
        log "SUCCESS" "Nginx genindlæst korrekt."
    else
        log "CRITICAL" "Fejl under genindlæsning af Nginx. Kontrollér konfigurationerne."
    fi
}

run_certbot() {
    log "INFO" "Forsøger at generere Let's Encrypt-certifikater..."
    for domain in proxmox.beanssi.dk hestia.beanssi.dk beanssi.dk; do
        if certbot certonly --nginx -d "$domain" --non-interactive --agree-tos --email admin@beanssi.dk; then
            log "SUCCESS" "Certifikat genereret for $domain."
        else
            log "ERROR" "Kunne ikke generere certifikat for $domain. Kontrollér fejlene."
        fi
    done
}

test_urls() {
    log "INFO" "Tester URL'er for Let's Encrypt validering..."
    for domain in proxmox.beanssi.dk hestia.beanssi.dk beanssi.dk; do
        url="http://$domain/.well-known/acme-challenge/testfile"
        response=$(curl -s -o /dev/null -w "%{http_code}" "$url")
        if [ "$response" -eq 200 ]; then
            log "SUCCESS" "URL fungerer korrekt: $url"
        else
            log "ERROR" "URL-test fejlede for $url. HTTP-kode: $response"
        fi
    done
}

main() {
    log "INFO" "Starter opsætning..."
    check_service_status "nginx"
    check_service_status "hestia"
    fix_port_conflict 8080
    fix_port_conflict 8083
    setup_nginx
    test_urls
    run_certbot
    log "INFO" "Opsætningen er fuldført!"
}

main
