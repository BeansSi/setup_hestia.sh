#!/bin/bash

LOG_FILE="/var/log/setup_hestia_full.log"
HESTIA_SERVICE="hestia"
NGINX_SERVICE="nginx"
NGINX_CONF_PATH="/etc/nginx/nginx.conf"
H_ESTIA_PORTS=(8083 8084)
WEB_DIR="/var/www/letsencrypt/.well-known/acme-challenge/"

# Funktion til logning
log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $level: $message"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $level: $message" >> "$LOG_FILE"
}

# Validerer og retter Nginx-konfigurationer
fix_nginx() {
    log "INFO" "Validerer Nginx-konfiguration..."
    if nginx -t > /dev/null 2>&1; then
        log "INFO" "Nginx-konfiguration er gyldig."
    else
        log "ERROR" "Nginx-konfigurationen har fejl. Her er detaljer:"
        nginx -t 2>&1 | tee -a "$LOG_FILE"
        exit 1
    fi

    log "INFO" "Tjekker for porte brugt af Nginx..."
    for port in 80 443; do
        if lsof -i :"$port" > /dev/null; then
            log "WARNING" "Port $port er i brug. Forsøger at frigøre..."
            fuser -k "$port"/tcp
            log "INFO" "Port $port frigjort."
        else
            log "INFO" "Port $port er fri."
        fi
    done

    log "INFO" "Genstarter Nginx..."
    systemctl restart $NGINX_SERVICE
    if systemctl is-active --quiet $NGINX_SERVICE; then
        log "SUCCESS" "Nginx kører korrekt."
    else
        log "CRITICAL" "Nginx kunne ikke starte. Tjek detaljer i $LOG_FILE."
        exit 1
    fi
}

# Fejlsøger og gendanner Hestia
fix_hestia() {
    log "INFO" "Starter fejlsøgning og rettelse for Hestia..."
    for port in "${H_ESTIA_PORTS[@]}"; do
        if lsof -i :"$port" > /dev/null; then
            log "WARNING" "Port $port er i brug. Stopper processer..."
            fuser -k "$port"/tcp
            log "INFO" "Port $port frigjort."
        else
            log "INFO" "Port $port er fri."
        fi
    done

    log "INFO" "Tjekker Hestia Nginx-konfiguration..."
    if /usr/local/hestia/nginx/sbin/nginx -t > /dev/null 2>&1; then
        log "INFO" "Hestia Nginx-konfiguration er gyldig."
    else
        log "ERROR" "Hestia-konfiguration har fejl. Se logfilen for detaljer."
        /usr/local/hestia/nginx/sbin/nginx -t 2>&1 | tee -a "$LOG_FILE"
        exit 1
    fi

    log "INFO" "Forsøger at genstarte Hestia..."
    systemctl restart $HESTIA_SERVICE
    if systemctl is-active --quiet $HESTIA_SERVICE; then
        log "SUCCESS" "Hestia kører korrekt."
    else
        log "CRITICAL" "Hestia kunne ikke starte. Kontrollér manuelt."
        exit 1
    fi
}

# Opretter nødvendige filer og mapper
prepare_environment() {
    log "INFO" "Kontrollerer og opretter nødvendige mapper..."
    if [[ ! -d "$WEB_DIR" ]]; then
        mkdir -p "$WEB_DIR"
        log "INFO" "Oprettede mappe: $WEB_DIR"
    else
        log "INFO" "Mappe findes allerede: $WEB_DIR"
    fi

    log "INFO" "Opretter testfiler..."
    echo "Test" > "${WEB_DIR}test_nginx"
    echo "Test" > "${WEB_DIR}test_hestia"
    log "INFO" "Testfiler oprettet."
}

# Kontrollerer tjenester
check_services() {
    log "INFO" "Kontrollerer status for Nginx..."
    if systemctl is-active --quiet $NGINX_SERVICE; then
        log "INFO" "Nginx kører korrekt."
    else
        log "ERROR" "Nginx kører ikke. Starter fejlsøgning..."
        fix_nginx
    fi

    log "INFO" "Kontrollerer status for Hestia..."
    if systemctl is-active --quiet $HESTIA_SERVICE; then
        log "INFO" "Hestia kører korrekt."
    else
        log "ERROR" "Hestia kører ikke. Starter fejlsøgning..."
        fix_hestia
    fi
}

# Hovedfunktion
main() {
    log "INFO" "Starter opsætning..."
    prepare_environment
    check_services
    log "SUCCESS" "Opsætning færdiggjort uden kritiske fejl!"
}

main
