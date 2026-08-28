#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${PG_BACKUP_LIB_DIR:-${SCRIPT_DIR}/lib}"

source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/version.sh"

readonly LOG_COMPONENT='pg-restore'

if [[ "${1:-}" == "--version" ]]; then
    printf 'pg-restore %s\n' "$(version::get)"
    exit 0
fi

require_env() {
    local name="$1"

    if [[ -z "${!name:-}" ]]; then
        log::error "$LOG_COMPONENT" "Required environment variable '$name' is not set."
        exit 1
    fi
}

load_password() {
    if [[ -n "${PGPASSWORD_FILE:-}" ]]; then
        if [[ ! -r "$PGPASSWORD_FILE" ]]; then
            log::error "$LOG_COMPONENT" "PGPASSWORD_FILE is not readable: $PGPASSWORD_FILE"
            exit 1
        fi

        PGPASSWORD="$(cat "$PGPASSWORD_FILE")"
        export PGPASSWORD
    fi
}

DUMP_FILE="${1:-}"

if [[ -z "$DUMP_FILE" ]]; then
    log::error "$LOG_COMPONENT" "Usage: pg-restore /path/to/backup.dump"
    exit 1
fi

if [[ ! -f "$DUMP_FILE" ]]; then
    log::error "$LOG_COMPONENT" "Backup file not found: $DUMP_FILE"
    exit 1
fi

require_env "PGHOST"
require_env "PGUSER"
require_env "PGDATABASE"

PGPORT="${PGPORT:-5432}"
PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-10}"

load_password

export PGCONNECT_TIMEOUT

log::info "$LOG_COMPONENT" "Starting PostgreSQL restore."
log::info "$LOG_COMPONENT" "Target: ${PGHOST}:${PGPORT}/${PGDATABASE}"
log::info "$LOG_COMPONENT" "Backup file: ${DUMP_FILE}"

if ! pg_isready \
    --host="$PGHOST" \
    --port="$PGPORT" \
    --username="$PGUSER" \
    --dbname=postgres \
    --timeout="$PGCONNECT_TIMEOUT" \
    >/dev/null 2>&1; then

    log::error "$LOG_COMPONENT" "PostgreSQL is not ready at ${PGHOST}:${PGPORT}."
    exit 1
fi

log::info "$LOG_COMPONENT" "Terminating active connections to database '${PGDATABASE}'."

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

log::info "$LOG_COMPONENT" "Dropping database '${PGDATABASE}' if it exists."

dropdb \
    --host="$PGHOST" \
    --port="$PGPORT" \
    --username="$PGUSER" \
    --if-exists \
    "$PGDATABASE"

log::info "$LOG_COMPONENT" "Creating database '${PGDATABASE}'."

createdb \
    --host="$PGHOST" \
    --port="$PGPORT" \
    --username="$PGUSER" \
    "$PGDATABASE"

case "$DUMP_FILE" in
    *.sql)
        log::info "$LOG_COMPONENT" "Detected plain SQL backup."

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
        log::info "$LOG_COMPONENT" "Restoring PostgreSQL custom-format backup."

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

log::info "$LOG_COMPONENT" "Restore completed successfully."
