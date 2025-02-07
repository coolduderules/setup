#!/bin/bash

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root" >&2
        if command -v sudo > /dev/null 2>&1; then
            echo "Attempting to re-run with sudo..."
            exec sudo -- "$0" "$@"
        else
            echo "sudo command not found. Please run as root" >&2
            exit 1
        fi
    fi
}

# Check required dependencies
check_dependencies() {
    local -r DEPS=(find grep sed awk mount umount sort lsof btrfs archinstall)
    local missing=()

    for cmd in "${DEPS[@]}"; do
        command -v "$cmd" > /dev/null 2>&1 || missing+=("$cmd")
    done

    if ((${#missing[@]} > 0)); then
        echo "Missing required commands: ${missing[*]}. Attempting to install..." >&2
	if (! pacman -S --noconfirm ${missing[*]}); then
	return 1
	fi
    fi
    return 0
}

# Find config file
find_config() {
    local found_config

    # First try explicit config
    if [[ -n ${CONFIG_FILE:-} && -f $CONFIG_FILE ]]; then
        echo "$CONFIG_FILE"
        return 0
    fi

    # Then try .private directories
    found_config=$(find "$SCRIPT_DIR" -path "*/\.private/*" -name "config.conf" -type f 2> /dev/null | head -n1)

    # Finally try other directories
    if [[ -z $found_config ]]; then
        found_config=$(find "$SCRIPT_DIR" -not -path "*/\.private/*" -name "config.conf" -type f 2> /dev/null | head -n1)
    fi

    echo "${found_config:-}"
    return 0
}

init_script() {
    check_root "$@"
    set -euo pipefail

    SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
    export SCRIPT_DIR

    SUFF="${SUFF:-}"
    export SUFF lin="LIN${SUFF}" esp="ESP${SUFF}"

    check_dependencies || exit 1

    export LOG_FILE="${LOG_FILE:-"$SCRIPT_DIR/.private/install.log"}"
    mkdir -p "$SCRIPT_DIR/.private" || :

    # Parse arguments if not already done
    if [[ -z ${CONFIG_FILE:-} ]]; then
        parse_args "$@"
    fi

    if [[ ! -f ${CONFIG_FILE:-} ]]; then
        log "Error: No valid configuration file found" "ERROR"
        exit 1
    fi

    log "Using config file: $CONFIG_FILE" "DEBUG"
    # shellcheck disable=SC1090
    source "$CONFIG_FILE" || error_handler ${LINENO} "Failed to source: $CONFIG_FILE" $?
    log "Successfully loaded config file" "DEBUG"

    trap 'error_handler ${LINENO} "$BASH_COMMAND" $?' ERR
    trap cleanup EXIT
}


log() {
    local message=$1
    local level=${2:-"INFO"}
    printf '[%s] [%s] %s\n' "$(date +"%Y-%m-%d %H:%M:%S")" "$level" "$message" \
        | tee -a "${LOG_FILE}"
}

error_handler() {
    local line=$1
    local cmd=$2
    local code=${3:-1}
    log "Error on line $line: '$cmd' failed with code $code" "ERROR"
    return "$code"
}

# Safer cleanup
cleanup() {
    local code=$?
    [[ $code -ne 0 ]] && log "Script failed with code $code" "ERROR"
    cleanup_mounts "${MOUNT_PATH:-}" || true
}

cleanup_mounts() {
    local target="${MOUNT_PATH:-1}"
    local mounts
    mounts=$(mount | grep "^.*on.*$target" | awk '{print $3}' | sort -r)

    while read -r path; do
        [[ -z $path ]] && continue
        umount -R "$path" 2> /dev/null || umount -l -R "$path" 2> /dev/null || true
    done <<< "$mounts"
}

# Export functions and initialize
export -f log error_handler cleanup cleanup_mounts init_script parse_args find_config check_dependencies
