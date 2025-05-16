#!/bin/bash

# Process template files with config values
process_template() {
    mkdir -p "$(dirname "$2")"

    # Create package list JSON array
    local pkg_list
    pkg_list=$(grep -v '^#' "$SCRIPT_DIR/lib/pkg.lst" | awk '{printf "\"%s\", ", $0}' | sed 's/, $//')

    # Process template
    sed -e "s|ROOT_PASSWORD|${ROOT_PASSWORD}|g" \
        -e "s|USER_PASSWORD|${USER_PASSWORD}|g" \
        -e "s|USER_NAME|${USER_NAME}|g" \
        -e "s|HOST_NAME|${HOST_NAME}|g" \
        -e "s|TIME_ZONE|${TIME_ZONE}|g" \
        -e "s|MOUNT_PATH|${MOUNT_PATH}|g" \
        -e "s|\"PACKAGE_LIST\"|[${pkg_list}]|g" \
        "$1" > "$2"
    chmod 600 "$2"
}

# Generate installation files from templates
generate_install_files() {
    mkdir -p "$SCRIPT_DIR/private"
    process_template "$SCRIPT_DIR/lib/user_configuration.json.template" \
        "$SCRIPT_DIR/private/tmp_user_configuration.json" || return 1
    process_template "$SCRIPT_DIR/lib/user_credentials.json.template" \
        "$SCRIPT_DIR/private/tmp_user_credentials.json" || return 1
    sed -e "s|MOUNT_PATH|${MOUNT_PATH}|g" \
        "$SCRIPT_DIR/lib/guided_bootless.py.template" > "$SCRIPT_DIR/private/tmp_guided_bootless.py" || return 1
}
export -f process_template generate_install_files
