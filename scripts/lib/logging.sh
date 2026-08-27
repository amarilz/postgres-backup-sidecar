#!/usr/bin/env bash

# Shared logging functions for production scripts and tests.

log::_use_color() {
    [[ -t 1 && -z "${NO_COLOR:-}" ]]
}

log::_color_for_level() {
    case "$1" in
        INFO) printf '\033[0;32m' ;;
        WARN) printf '\033[0;33m' ;;
        ERROR) printf '\033[0;31m' ;;
        *) printf '' ;;
    esac
}

log::write() {
    local level="$1"
    local component="$2"
    shift 2

    local color=''
    local reset=''
    local output_fd=1

    if [[ "$level" == "ERROR" ]]; then
        output_fd=2
    fi

    if log::_use_color; then
        color="$(log::_color_for_level "$level")"
        reset='\033[0m'
    fi

    printf '[%s] %b[%s]%b [%s] %s\n' \
        "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        "$color" "$level" "$reset" \
        "$component" "$*" \
        >&"$output_fd"
}

log::info() {
    local component="$1"
    shift
    log::write INFO "$component" "$@"
}

log::warn() {
    local component="$1"
    shift
    log::write WARN "$component" "$@"
}

log::error() {
    local component="$1"
    shift
    log::write ERROR "$component" "$@"
}
