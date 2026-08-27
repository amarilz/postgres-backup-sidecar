#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")"
    pwd
)"

CASES_DIR="${SCRIPT_DIR}/cases"
source "${SCRIPT_DIR}/../scripts/lib/logging.sh"
readonly LOG_COMPONENT='test-suite'

if [[ ! -d "$CASES_DIR" ]]; then
    log::error "$LOG_COMPONENT" "Cases directory not found: $CASES_DIR"
    exit 1
fi

TEST_COUNT="$(
    find "$CASES_DIR" \
        -maxdepth 1 \
        -type f \
        -name '*.sh' \
        | wc -l \
        | tr -d ' '
)"

if [[ "$TEST_COUNT" -eq 0 ]]; then
    log::error "$LOG_COMPONENT" "No test cases found in $CASES_DIR"
    exit 1
fi

log::info "$LOG_COMPONENT" "Found ${TEST_COUNT} test case(s)."

PASSED=0

while IFS= read -r TEST_CASE; do
    TEST_NAME="$(basename "$TEST_CASE")"

    log::info "$LOG_COMPONENT" "Running: $TEST_NAME"

    if bash "$TEST_CASE"; then
        log::info "$LOG_COMPONENT" "PASS: $TEST_NAME"
        PASSED=$((PASSED + 1))
    else
        log::error "$LOG_COMPONENT" "$TEST_NAME"
        log::error "$LOG_COMPONENT" "Test suite stopped after first failure."
        exit 1
    fi
done < <(
    find "$CASES_DIR" \
        -maxdepth 1 \
        -type f \
        -name '*.sh' \
        | sort
)

printf '\n========================================\n'
printf 'Test suite completed successfully.\n'
printf 'Passed: %d/%d\n' "$PASSED" "$TEST_COUNT"
printf '========================================\n'
