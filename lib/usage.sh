#!/bin/bash

# Parse command line options
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
        -r | --recreate)
            RECREATE_SUBVOLS=1
            shift
            ;;
        -m | --mountonly)
            MOUNT_ONLY=1
            shift
            ;;
        -c | --config)
            if [[ -n $2 && ! $2 =~ ^- ]]; then
                CONFIG_FILE="$2"
                shift 2
            else
                log "Error: --config/-c requires a file argument" "ERROR"
                usage 1
            fi
            ;;
        -h | --help)
            usage 0
            ;;
        -*)
            log "Error: Unknown option $1" "ERROR"
            usage 1
            ;;
        *)
            if [[ -f $1 ]]; then
                CONFIG_FILE="$1"
            else
                log "Warning: Ignored invalid config file: $1" "WARN"
            fi
            shift
            ;;
        esac
    done
    if [[ -z ${CONFIG_FILE:-} ]]; then
        CONFIG_FILE="$(find_config)"
    fi
    export CONFIG_FILE RECREATE_SUBVOLS MOUNT_ONLY
}

# Display usage information
usage() {
    cat << EOF
Usage: $(basename "$0") [-r|--recreate] [-m|--mountonly] [-c|--config FILE] [config_file]

Options:
    -r, --recreate       Recreate all subvolumes
    -m, --mountonly     Mount filesystems only without installation
    -c, --config FILE    Use specific config file
    -h, --help          Show this help message

Arguments:
    config_file    Alternative way to specify config file

Environment:
    SCRIPT_DIR    Base directory for all operations
    CONFIG_FILE   Configuration file path (default: first found config.conf)
    LOG_FILE      Log file path (default: \$SCRIPT_DIR/.private/install.log)

Config Variables:
    USER_NAME       Username for the system
    USER_PASSWORD   User's password
    ROOT_PASSWORD   Root password
    HOST_NAME       System hostname
    TIME_ZONE      System timezone
    SUFF           Suffix for disk labels (e.g., USB, MAC, NET)
    MOUNT_PATH     Installation mount point
    RECREATE       Delete and recreate subvolumes (easier on drives compared to full mkfs)
    MOUNT_ONLY     (deprecated with the usage of "${SCRIPT_DIR}"/scripts/mount_btrfs.sh preferred)
    SUBVOLUMES     BTRFS subvolume definitions

Example:
    $(basename "$0") -r -c custom.conf
    SUFF=USB $(basename "$0")
EOF
    exit "${1:-0}"
}
export -f usage parse_args
