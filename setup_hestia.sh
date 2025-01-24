#!/bin/bash

log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $level: $message"
}

check_and_restart_service() {
    local service="$1"
    log "INFO" "Kontrollerer status for $service..."
    if ! systemctl is-active --quiet "$service"; then
        log "ERROR" "$service kører ikke. Forsøger at genstarte..."
        systemctl restart "$service"
        if systemctl is-active --quiet "$service"; then
            log "SUCCESS" "$service genstartet korrekt."
        else
            log "CRITICAL" "Kunne ikke genstarte $service. Kontrollér manuelt."
            exit 1
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

delete_and_recreate_files() {
    log "INFO" "Sletter og genopretter nødvendige filer..."
    # Slet eksisterende konfigurationsfiler
    for domain in proxmox.beanssi.dk hestia.beanssi.dk beanssi.dk; do
        conf_path="/etc/nginx/conf.d/$domain.conf"
        if [ -f "$conf_path" ]; then
            rm "$conf_path"
            log "SUCCESS" "Fil slettet: $conf_path"
        else
            log "INFO" "Fil findes ikke: $conf_path"
        fi
    done

    # Slet gamle certifikatfiler
    for domain in proxmox.beanssi.dk hestia.beanssi.dk beanssi.dk; do
        cert_path="/etc/letsencrypt/live/$domain"
        if [ -d "$cert_path" ]; then
            rm -rf "$cert_path"
            log "SUCCESS" "Certifikatfiler slettet: $cert_path"
        else
            log "INFO" "Certifikatfiler findes ikke: $cert_path"
        fi
    done

    # Genopret konfigurationsfiler
    create_nginx_configs
}

create_nginx_configs() {
    log "INFO" "Opretter nye Nginx-konfigurationsfiler..."
    for domain in proxmox.beanssi.dk hestia.beanssi.dk beanssi.dk; do
        cat <<EOF > /etc/nginx/conf.d/$domain.conf
server {
    listen 80;
    server_name $domain;

    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF
        log "SUCCESS" "Konfigurationsfil oprettet: /etc/nginx/conf.d/$domain.conf"
    done
}

test_and_reload_nginx() {
    log "INFO" "Tester og genindlæser Nginx-konfiguration..."
    if nginx -t; then
        systemctl reload nginx
        log "SUCCESS" "Nginx genindlæst korrekt."
    else
        log "CRITICAL" "Fejl i Nginx-konfigurationen. Kontrollér og ret fejlene manuelt."
        exit 1
    fi
}

run_certbot() {
    log "INFO" "Forsøger at generere Let's Encrypt-certifikater..."
    for domain in proxmox.beanssi.dk hestia.beanssi.dk beanssi.dk; do
        if certbot certonly --nginx -d "$domain" --non-interactive --agree-tos --email admin@beanssi.dk; then
            log "SUCCESS" "Certifikat genereret for $domain."
        else
            log "ERROR" "Kunne ikke generere certifikat for $domain. Forsøger at rette fejl."
            delete_and_recreate_files
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
            log "INFO" "Forsøger at rette fejl automatisk..."
            run_certbot
        fi
    done
}

main() {
    log "INFO" "Starter opsætning..."
    check_and_restart_service "nginx"
    check_and_restart_service "hestia"
    fix_port_conflict 8080
    fix_port_conflict 8083
    delete_and_recreate_files
    test_and_reload_nginx
    test_urls
    log "INFO" "Opsætningen er fuldført!"
}

main
