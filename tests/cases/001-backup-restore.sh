#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")"
    pwd
)"

source "${SCRIPT_DIR}/../lib/test-lib.sh"

trap cleanup_test_environment EXIT

cd "$SCRIPT_DIR"

##################################################
log::info "$TEST_LOG_COMPONENT" "Cleaning previous test artifacts."
rm -rf "${TESTS_DIR}/backups"
mkdir -p "${TESTS_DIR}/backups"

# The backup container runs as UID/GID 10001.
chmod 0777 "${TESTS_DIR}/backups"

##################################################
log::info "$TEST_LOG_COMPONENT" "Building backup image."
docker compose \
    -f "$COMPOSE_FILE" \
    build \
    --build-arg VERSION="$PROJECT_VERSION" \
    backup

##################################################
log::info "$TEST_LOG_COMPONENT" "Starting PostgreSQL."
docker compose \
    -f "$COMPOSE_FILE" \
    up \
    -d postgres

##################################################
wait_for_postgres

##################################################
log::info "$TEST_LOG_COMPONENT" "Populating database with deterministic test data."
docker compose \
    -f "$COMPOSE_FILE" \
    exec -T postgres \
    psql \
        -U testuser \
        -d testdb \
        -v ON_ERROR_STOP=1 \
    < ../init/001-test-data.sql

##################################################
log::info "$TEST_LOG_COMPONENT" "Calculating fingerprint before backup."
FINGERPRINT_BEFORE="$(
    docker compose \
        -f "$COMPOSE_FILE" \
        exec -T postgres \
        psql \
            -U testuser \
            -d testdb \
            -tA \
            -v ON_ERROR_STOP=1 \
        < ../assertions/fingerprint.sql
)"

if [[ -z "$FINGERPRINT_BEFORE" ]]; then
    log::error "$TEST_LOG_COMPONENT" "Could not calculate fingerprint before backup."
    exit 1
fi
log::info "$TEST_LOG_COMPONENT" "Fingerprint before backup: $FINGERPRINT_BEFORE"

##################################################
log::info "$TEST_LOG_COMPONENT" "Running assertions before backup."
docker compose \
    -f "$COMPOSE_FILE" \
    exec -T postgres \
    psql \
        -U testuser \
        -d testdb \
        -v ON_ERROR_STOP=1 \
    < ../assertions/verify.sql

log::info "$TEST_LOG_COMPONENT" "Creating backup."
docker compose \
    -f "$COMPOSE_FILE" \
    run \
    --rm \
    backup \
    pg-backup

BACKUP_FILE="$(
    find "${TESTS_DIR}/backups" \
        -maxdepth 1 \
        -type f \
        -name 'testdb_*.dump' \
        | sort \
        | tail -n 1
)"

if [[ -z "$BACKUP_FILE" ]]; then
    log::error "$TEST_LOG_COMPONENT" "Backup file was not created."
    exit 1
fi
if [[ ! -s "$BACKUP_FILE" ]]; then
    log::error "$TEST_LOG_COMPONENT" "Backup file exists but is empty: $BACKUP_FILE"
    exit 1
fi
log::info "$TEST_LOG_COMPONENT" "PASS: Backup created: $(basename "$BACKUP_FILE")"

##################################################
log::info "$TEST_LOG_COMPONENT" "Corrupting database intentionally."
docker compose \
    -f "$COMPOSE_FILE" \
    exec -T postgres \
    psql \
        -U testuser \
        -d testdb \
        -v ON_ERROR_STOP=1 \
        -c "
            DELETE FROM events;
            DELETE FROM projects;
            DELETE FROM users;
        "

##################################################
log::info "$TEST_LOG_COMPONENT" "Verifying database is now different from backup state."
USER_COUNT="$(
    docker compose \
        -f "$COMPOSE_FILE" \
        exec -T postgres \
        psql \
            -U testuser \
            -d testdb \
            -tAc "SELECT COUNT(*) FROM users;"
)"

if [[ "$USER_COUNT" != "0" ]]; then
    log::error "$TEST_LOG_COMPONENT" "Database corruption step failed."
    exit 1
fi

##################################################
log::info "$TEST_LOG_COMPONENT" "Restoring backup."
BACKUP_BASENAME="$(basename "$BACKUP_FILE")"
docker compose \
    -f "$COMPOSE_FILE" \
    run \
    --rm \
    backup \
    pg-restore \
    "/backups/${BACKUP_BASENAME}"

##################################################
log::info "$TEST_LOG_COMPONENT" "Running assertions after restore."
docker compose \
    -f "$COMPOSE_FILE" \
    exec -T postgres \
    psql \
        -U testuser \
        -d testdb \
        -v ON_ERROR_STOP=1 \
    < "${TESTS_DIR}/assertions/verify.sql"

##################################################
log::info "$TEST_LOG_COMPONENT" "Calculating fingerprint after restore."
FINGERPRINT_AFTER="$(
    docker compose \
        -f "$COMPOSE_FILE" \
        exec -T postgres \
        psql \
            -U testuser \
            -d testdb \
            -tA \
            -v ON_ERROR_STOP=1 \
        < "${TESTS_DIR}/assertions/fingerprint.sql"
)"

if [[ -z "$FINGERPRINT_AFTER" ]]; then
    log::error "$TEST_LOG_COMPONENT" "Could not calculate fingerprint after restore."
    exit 1
fi
log::info "$TEST_LOG_COMPONENT" "Fingerprint after restore: $FINGERPRINT_AFTER"
if [[ "$FINGERPRINT_BEFORE" != "$FINGERPRINT_AFTER" ]]; then
    log::error "$TEST_LOG_COMPONENT" "Database fingerprint mismatch after restore."
    log::error "$TEST_LOG_COMPONENT" "Before: $FINGERPRINT_BEFORE"
    log::error "$TEST_LOG_COMPONENT" "After:  $FINGERPRINT_AFTER"
    exit 1
fi
log::info "$TEST_LOG_COMPONENT" "PASS: Database fingerprint matches."

##################################################
log::info "$TEST_LOG_COMPONENT" "PASS: Backup and restore test completed successfully."
