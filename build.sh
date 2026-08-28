#!/usr/bin/env bash

set -Eeuo pipefail

NAMESPACE="${1:-amarilz}"

PROJECT_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")"
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

IMAGE_TAG="${NAMESPACE}/postgres-backup-sidecar:${VERSION}"

docker build \
    --build-arg VERSION="$VERSION" \
    --tag "$IMAGE_TAG" \
    "$PROJECT_DIR"


read -p "Do you want to push '$IMAGE_TAG' to Docker Hub? (y/N) " -n 1 -r REPLY
printf '\n'

if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    docker image push "$IMAGE_TAG"
fi
