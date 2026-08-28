#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")"
    pwd
)"

PROJECT_DIR="$(
    cd "${SCRIPT_DIR}/.."
    pwd
)"

VERSION="$(
    tr -d '\r\n' < "${PROJECT_DIR}/VERSION"
)"

if [[ -z "$VERSION" ]]; then
    printf 'VERSION file is empty.\n' >&2
    exit 1
fi

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'Invalid project version: %s\n' "$VERSION" >&2
    exit 1
fi

docker build \
    --build-arg VERSION="$VERSION" \
    --tag "postgres-backup-sidecar:${VERSION}" \
    "$PROJECT_DIR"
