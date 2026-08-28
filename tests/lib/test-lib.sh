#!/usr/bin/env bash

TESTS_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/.."
    pwd
)"

COMPOSE_FILE="${TESTS_DIR}/docker-compose.yml"
PROJECT_VERSION="$(
    tr -d '\r\n' < "${TESTS_DIR}/../VERSION"
)"
TEST_CASE_NAME="$(basename "${BASH_SOURCE[1]}")"
TEST_LOG_COMPONENT="test:${TEST_CASE_NAME}"

source "${TESTS_DIR}/../scripts/lib/logging.sh"

compose() {
    docker compose \
        -f "$COMPOSE_FILE" \
        "$@"
}

cleanup_test_environment() {
    compose down \
        --volumes \
        --remove-orphans \
        >/dev/null 2>&1 || true

    rm -rf "${TESTS_DIR}/backups"
}

wait_for_postgres() {
    log::info "$TEST_LOG_COMPONENT" "Waiting for PostgreSQL."

    until compose exec -T postgres \
        pg_isready \
            -U testuser \
            -d testdb \
            >/dev/null 2>&1; do

        sleep 1
    done
}
