#!/usr/bin/env bash

version::get() {
    local version_file="${PG_BACKUP_VERSION_FILE:-/usr/local/share/pg-backup/VERSION}"

    if [[ ! -r "$version_file" ]]; then
        printf 'unknown\n'
        return 1
    fi

    tr -d '\r\n' < "$version_file"
}