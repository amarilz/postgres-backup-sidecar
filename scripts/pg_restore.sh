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

DUMP_FILE="${1:-}"

if [[ -z "$DUMP_FILE" ]]; then
    error "Usage: pg-restore /path/to/backup.dump"
    exit 1
fi

if [[ ! -f "$DUMP_FILE" ]]; then
    error "Backup file not found: $DUMP_FILE"
    exit 1
fi

require_env "PGHOST"
require_env "PGUSER"
require_env "PGDATABASE"

PGPORT="${PGPORT:-5432}"
PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-10}"

load_password

export PGCONNECT_TIMEOUT

log "Starting PostgreSQL restore."
log "Target: ${PGHOST}:${PGPORT}/${PGDATABASE}"
log "Backup file: ${DUMP_FILE}"

if ! pg_isready \
    --host="$PGHOST" \
    --port="$PGPORT" \
    --username="$PGUSER" \
    --dbname=postgres \
    --timeout="$PGCONNECT_TIMEOUT" \
    >/dev/null 2>&1; then

    error "PostgreSQL is not ready at ${PGHOST}:${PGPORT}."
    exit 1
fi

log "Terminating active connections to database '${PGDATABASE}'."

psql \
    --host="$PGHOST" \
    --port="$PGPORT" \
    --username="$PGUSER" \
    --dbname=postgres \
    --no-password \
    --set=ON_ERROR_STOP=1 \
    --set=db_name="$PGDATABASE" \
    <<'SQL'
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = :'db_name'
  AND pid <> pg_backend_pid();
SQL

log "Dropping database '${PGDATABASE}' if it exists."

dropdb \
    --host="$PGHOST" \
    --port="$PGPORT" \
    --username="$PGUSER" \
    --if-exists \
    "$PGDATABASE"

log "Creating database '${PGDATABASE}'."

createdb \
    --host="$PGHOST" \
    --port="$PGPORT" \
    --username="$PGUSER" \
    "$PGDATABASE"

case "$DUMP_FILE" in
    *.sql)
        log "Detected plain SQL backup."

        psql \
            --host="$PGHOST" \
            --port="$PGPORT" \
            --username="$PGUSER" \
            --dbname="$PGDATABASE" \
            --no-password \
            --set=ON_ERROR_STOP=1 \
            < "$DUMP_FILE"
        ;;

    *)
        log "Restoring PostgreSQL custom-format backup."

        pg_restore \
            --host="$PGHOST" \
            --port="$PGPORT" \
            --username="$PGUSER" \
            --dbname="$PGDATABASE" \
            --no-password \
            --exit-on-error \
            --verbose \
            "$DUMP_FILE"
        ;;
esac

log "Restore completed successfully."
