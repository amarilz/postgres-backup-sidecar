#!/usr/bin/env bash

set -Eeuo pipefail

INTERVAL="${BACKUP_INTERVAL_SECONDS:-3600}"
PGPORT="${PGPORT:-5432}"
PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-10}"

if [[ -z "${PGHOST:-}" || -z "${PGUSER:-}" || -z "${PGDATABASE:-}" ]]; then
    exit 1
fi

if [[ -n "${PGPASSWORD_FILE:-}" ]]; then
    if [[ ! -r "$PGPASSWORD_FILE" ]]; then
        exit 1
    fi

    PGPASSWORD="$(cat "$PGPASSWORD_FILE")"
    export PGPASSWORD
fi

export PGCONNECT_TIMEOUT

if ! pg_isready \
    --host="$PGHOST" \
    --port="$PGPORT" \
    --username="$PGUSER" \
    --dbname="$PGDATABASE" \
    --timeout="$PGCONNECT_TIMEOUT" \
    >/dev/null 2>&1; then

    exit 1
fi

LAST_SUCCESS_FILE="/var/lib/pg-backup/last-success"

if [[ ! -f "$LAST_SUCCESS_FILE" ]]; then
    exit 1
fi

LAST_SUCCESS="$(cat "$LAST_SUCCESS_FILE")"
NOW="$(date +%s)"

if ! [[ "$LAST_SUCCESS" =~ ^[0-9]+$ ]]; then
    exit 1
fi

MAX_AGE="${HEALTHCHECK_MAX_AGE_SECONDS:-$((INTERVAL * 2 + 300))}"

AGE="$((NOW - LAST_SUCCESS))"

if (( AGE > MAX_AGE )); then
    exit 1
fi

exit 0
