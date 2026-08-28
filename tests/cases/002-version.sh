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
log::info "$TEST_LOG_COMPONENT" "Building backup image."

docker compose \
    -f "$COMPOSE_FILE" \
    build \
    --build-arg VERSION="$PROJECT_VERSION" \
    backup

##################################################
log::info "$TEST_LOG_COMPONENT" "Checking pg-backup version."

BACKUP_VERSION="$(
    docker compose \
        -f "$COMPOSE_FILE" \
        run \
        --rm \
        backup \
        pg-backup \
        --version
)"

if [[ "$BACKUP_VERSION" != "pg-backup ${PROJECT_VERSION}" ]]; then
    log::error "$TEST_LOG_COMPONENT" \
        "Unexpected pg-backup version: ${BACKUP_VERSION}"
    exit 1
fi

log::info "$TEST_LOG_COMPONENT" \
    "PASS: pg-backup reports version ${PROJECT_VERSION}."

##################################################
log::info "$TEST_LOG_COMPONENT" "Checking pg-restore version."

RESTORE_VERSION="$(
    docker compose \
        -f "$COMPOSE_FILE" \
        run \
        --rm \
        backup \
        pg-restore \
        --version
)"

if [[ "$RESTORE_VERSION" != "pg-restore ${PROJECT_VERSION}" ]]; then
    log::error "$TEST_LOG_COMPONENT" \
        "Unexpected pg-restore version: ${RESTORE_VERSION}"
    exit 1
fi

log::info "$TEST_LOG_COMPONENT" \
    "PASS: pg-restore reports version ${PROJECT_VERSION}."

##################################################
log::info "$TEST_LOG_COMPONENT" \
    "PASS: Version test completed successfully."
