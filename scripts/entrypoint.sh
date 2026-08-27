#!/usr/bin/env bash

set -Eeuo pipefail

log() {
    printf '[%s] [INFO] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
}

error() {
    printf '[%s] [ERROR] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >&2
}

is_true() {
    case "${1,,}" in
        true|1|yes|y|on)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

if [[ $# -gt 0 ]]; then
    case "$1" in
        pg-backup)
            exec /usr/local/bin/pg-backup
            ;;

        pg-restore)
            shift
            exec /usr/local/bin/pg-restore "$@"
            ;;

        *)
            exec "$@"
            ;;
    esac
fi

validate_positive_integer() {
    local value="$1"
    local name="$2"

    if ! [[ "$value" =~ ^[0-9]+$ ]] || (( value <= 0 )); then
        error "$name must be a positive integer. Current value: $value"
        exit 1
    fi
}

INTERVAL="${BACKUP_INTERVAL_SECONDS:-3600}"
BACKUP_ON_START="${BACKUP_ON_START:-true}"
BACKUP_ON_SHUTDOWN="${BACKUP_ON_SHUTDOWN:-true}"

validate_positive_integer \
    "$INTERVAL" \
    "BACKUP_INTERVAL_SECONDS"

SLEEP_PID=""

run_backup() {
    if ! /usr/local/bin/pg-backup; then
        error "Backup failed. The container will continue running."
        return 1
    fi

    return 0
}

shutdown() {
    log "Shutdown signal received."

    if [[ -n "${SLEEP_PID}" ]]; then
        kill "${SLEEP_PID}" 2>/dev/null || true
        wait "${SLEEP_PID}" 2>/dev/null || true
        SLEEP_PID=""
    fi

    if is_true "$BACKUP_ON_SHUTDOWN"; then
        log "Running final backup before shutdown."

        if ! run_backup; then
            error "Final backup failed."
        fi
    fi

    log "Backup service stopped."
    exit 0
}

trap shutdown SIGTERM SIGINT

log "PostgreSQL backup service starting."
log "Backup interval: ${INTERVAL} seconds."
log "Backup directory: ${BACKUP_DIR:-/backups}."
log "Backup retention: ${BACKUP_RETENTION_DAYS:-14} days."

if is_true "$BACKUP_ON_START"; then
    log "Running initial backup."
    run_backup || true
fi

while true; do
    sleep "$INTERVAL" &
    SLEEP_PID=$!

    wait "$SLEEP_PID" || true
    SLEEP_PID=""

    run_backup || true
done
