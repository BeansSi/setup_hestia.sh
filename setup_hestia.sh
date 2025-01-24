#!/bin/bash

log_file="/var/log/setup_hestia.log"

# Funktion til logning
log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $level: $message"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $level: $message" >> "$log_file"
}

# Funktion til fejlsøgning af Hestia
troubleshoot_hestia() {
    log "INFO" "Starter fejlsøgning for hestia.service..."

    # Tjekker systemlog for fejl
    log "INFO" "Indsamler de sidste 50 linjer fra systemloggen for hestia.service."
    journalctl -u hestia.service -n 50 >> "$log_file"

    # Tjekker, om porte er blokeret
    for port in 8083 8084; do
        log "INFO" "Tjekker, om port $port er i brug..."
        if lsof -i :"$port" > /dev/null; then
            log "WARNING" "Port $port er i brug. Stopper processer..."
            fuser -k "$port"/tcp
            log "INFO" "Port $port frigjort."
        else
            log "INFO" "Port $port er fri."
        fi
    done

    # Tjekker Hestia-konfiguration
    if [[ -f "/usr/local/hestia/nginx/conf/nginx.conf" ]]; then
        log "INFO" "Kontrollerer Hestia Nginx-konfiguration..."
        if nginx -t -c /usr/local/hestia/nginx/conf/nginx.conf; then
            log "INFO" "Hestia Nginx-konfigurationen er gyldig."
        else
            log "ERROR" "Hestia Nginx-konfigurationen er ugyldig. Kontrollér manuelt."
            nginx -t -c /usr/local/hestia/nginx/conf/nginx.conf >> "$log_file"
        fi
    else
        log "ERROR" "Hestia Nginx-konfigurationsfil mangler!"
    fi

    # Prøver at genstarte Hestia
    log "INFO" "Forsøger at genstarte hestia.service igen..."
    systemctl restart hestia
    if systemctl is-active --quiet hestia; then
        log "SUCCESS" "hestia.service genstartet korrekt."
    else
        log "CRITICAL" "Kunne stadig ikke starte hestia.service. Kontrollér manuelt."
        exit 1
    fi
}

# Funktion til at kontrollere en tjeneste
check_service() {
    local service="$1"
    log "INFO" "Kontrollerer status for $service..."
    if systemctl is-active --quiet "$service"; then
        log "INFO" "$service kører korrekt."
    else
        log "ERROR" "$service kører ikke. Forsøger at genstarte..."
        systemctl restart "$service"
        if ! systemctl is-active --quiet "$service"; then
            log "CRITICAL" "Kunne ikke genstarte $service. Starter fejlsøgning..."
            [[ "$service" == "hestia" ]] && troubleshoot_hestia
            exit 1
        else
            log "SUCCESS" "$service genstartet korrekt."
        fi
    fi
}

# Funktion til at slette gamle Nginx-konfigurationer
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

# Hovedfunktion
main() {
    log "INFO" "Starter opsætning..."
    check_service "nginx"
    check_service "hestia"
    reset_nginx_config
    log "SUCCESS" "Opsætningen er fuldført!"
}

main
