#!/usr/bin/env bash

set -Eeuo pipefail

log() {
    printf '[%s] [INFO] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
}

error() {
    printf '[%s] [ERROR] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >&2
}

require_env() {
    local name="$1"

    if [[ -z "${!name:-}" ]]; then
        error "Required environment variable '$name' is not set."
        exit 1
    fi
}

validate_non_negative_integer() {
    local value="$1"
    local name="$2"

    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        error "$name must be a non-negative integer. Current value: $value"
        exit 1
    fi
}

load_password() {
    if [[ -n "${PGPASSWORD_FILE:-}" ]]; then
        if [[ ! -r "$PGPASSWORD_FILE" ]]; then
            error "PGPASSWORD_FILE is not readable: $PGPASSWORD_FILE"
            exit 1
        fi

        PGPASSWORD="$(cat "$PGPASSWORD_FILE")"
        export PGPASSWORD
    fi
}

cleanup_temp_file() {
    if [[ -n "${TEMP_FILE:-}" && -f "${TEMP_FILE}" ]]; then
        rm -f "${TEMP_FILE}"
    fi
}

require_env "PGHOST"
require_env "PGUSER"
require_env "PGDATABASE"

PGPORT="${PGPORT:-5432}"
BACKUP_DIR="${BACKUP_DIR:-/backups}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
BACKUP_COMPRESSION="${BACKUP_COMPRESSION:-6}"
PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-10}"

validate_non_negative_integer "$BACKUP_RETENTION_DAYS" "BACKUP_RETENTION_DAYS"
validate_non_negative_integer "$BACKUP_COMPRESSION" "BACKUP_COMPRESSION"

load_password

export PGCONNECT_TIMEOUT

if [[ ! -d "$BACKUP_DIR" ]]; then
    error "Backup directory does not exist: $BACKUP_DIR"
    exit 1
fi

if [[ ! -w "$BACKUP_DIR" ]]; then
    error "Backup directory is not writable: $BACKUP_DIR"
    exit 1
fi

SAFE_DATABASE_NAME="$(
    printf '%s' "$PGDATABASE" \
        | tr -c '[:alnum:]_.-' '_'
)"

TIMESTAMP="$(date -u '+%Y%m%dT%H%M%SZ')"

BACKUP_FILE="${BACKUP_DIR}/${SAFE_DATABASE_NAME}_${TIMESTAMP}.dump"
TEMP_FILE="${BACKUP_FILE}.tmp"

trap cleanup_temp_file EXIT

log "Starting backup."
log "Database: ${PGDATABASE}"
log "Host: ${PGHOST}:${PGPORT}"

if ! pg_isready \
    --host="$PGHOST" \
    --port="$PGPORT" \
    --username="$PGUSER" \
    --dbname="$PGDATABASE" \
    --timeout="$PGCONNECT_TIMEOUT" \
    >/dev/null 2>&1; then

    error "PostgreSQL is not ready at ${PGHOST}:${PGPORT}."
    exit 1
fi

START_TIME="$(date +%s)"

pg_dump \
    --host="$PGHOST" \
    --port="$PGPORT" \
    --username="$PGUSER" \
    --dbname="$PGDATABASE" \
    --format=custom \
    --compress="$BACKUP_COMPRESSION" \
    --no-password \
    --file="$TEMP_FILE"

mv "$TEMP_FILE" "$BACKUP_FILE"

END_TIME="$(date +%s)"
DURATION="$((END_TIME - START_TIME))"

BACKUP_SIZE="$(du -h "$BACKUP_FILE" | cut -f1)"

log "Backup completed successfully."
log "File: $BACKUP_FILE"
log "Size: $BACKUP_SIZE"
log "Duration: ${DURATION}s"

date +%s > /var/lib/pg-backup/last-success

if (( BACKUP_RETENTION_DAYS > 0 )); then
    log "Removing backups older than ${BACKUP_RETENTION_DAYS} days."

    find "$BACKUP_DIR" \
        -type f \
        -name "${SAFE_DATABASE_NAME}_*.dump" \
        -mtime "+${BACKUP_RETENTION_DAYS}" \
        -delete
fi

trap - EXIT
