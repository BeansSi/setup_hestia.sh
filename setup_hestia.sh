#!/bin/bash

log_file="/var/log/setup_hestia.log"

# Funktion til logning
log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $level: $message"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $level: $message" >> "$log_file"
}

# Funktion til fejlsøgning og rettelse af hestia.service
fix_hestia_service() {
    log "INFO" "Starter fejlsøgning og rettelse for hestia.service..."

    # Tjek systemd-log for detaljer
    log "INFO" "Indsamler de sidste 50 linjer fra systemloggen for hestia.service."
    journalctl -u hestia.service -n 50 >> "$log_file"

    # Tjekker, om Hestias nødvendige porte er blokeret
    for port in 8083 8084; do
        log "INFO" "Tjekker, om port $port er i brug..."
        if lsof -i :"$port" > /dev/null; then
            log "WARNING" "Port $port er i brug. Stopper processer, der bruger porten..."
            fuser -k "$port"/tcp
            log "INFO" "Port $port frigjort."
        else
            log "INFO" "Port $port er fri."
        fi
    done

    # Tjekker Hestia-konfigurationsfiler
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

    # Prøver at genstarte Hestia-tjenesten
    log "INFO" "Forsøger at genstarte hestia.service..."
    systemctl restart hestia
    if systemctl is-active --quiet hestia; then
        log "SUCCESS" "hestia.service genstartet korrekt."
    else
        log "CRITICAL" "Kunne stadig ikke starte hestia.service. Kontrollér følgende log for detaljer:"
        journalctl -u hestia.service -n 50 | tee -a "$log_file"
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
