#!/bin/bash

log_file="/var/log/setup_hestia.log"

# Funktion til logning
log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $level: $message"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $level: $message" >> "$log_file"
}

# Funktion til fejlsøgning og rettelse af Nginx
fix_nginx_service() {
    log "INFO" "Starter fejlsøgning og rettelse for nginx.service..."

    # Tjekker Nginx-konfiguration
    log "INFO" "Validerer Nginx-konfiguration..."
    if nginx -t > /dev/null 2>&1; then
        log "INFO" "Nginx-konfigurationen er gyldig."
    else
        log "ERROR" "Nginx-konfigurationen er ugyldig. Her er detaljer:"
        nginx -t 2>&1 | tee -a "$log_file"
        exit 1
    fi

    # Tjekker efter brugte porte
    for port in 80 443; do
        log "INFO" "Tjekker, om port $port er i brug..."
        if lsof -i :"$port" > /dev/null; then
            log "WARNING" "Port $port er i brug. Stopper processer, der bruger porten..."
            fuser -k "$port"/tcp
            log "INFO" "Port $port frigjort."
        else
            log "INFO" "Port $port er fri."
        fi
    done

    # Genstarter Nginx
    log "INFO" "Forsøger at genstarte nginx.service..."
    systemctl restart nginx
    if systemctl is-active --quiet nginx; then
        log "SUCCESS" "nginx.service genstartet korrekt."
    else
        log "CRITICAL" "Kunne ikke genstarte nginx.service. Kontrollér følgende log for detaljer:"
        journalctl -u nginx.service -n 50 | tee -a "$log_file"
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
            [[ "$service" == "nginx" ]] && fix_nginx_service
            [[ "$service" == "hestia" ]] && fix_hestia_service
            exit 1
        else
            log "SUCCESS" "$service genstartet korrekt."
        fi
    fi
}

# Hovedfunktion
main() {
    log "INFO" "Starter opsætning..."
    check_service "nginx"
    check_service "hestia"
    log "SUCCESS" "Opsætningen er fuldført uden kritiske fejl!"
}

main
