#!/bin/bash
#shellcheck disable=SC1090
source "$CONFIG_FILE"

# Copy files
#while read -r copy; do
#    rsync -axHAWXSR --info=progress2 "${copy}" "$MOUNT_PATH"
#done < <(sed "s|~|/home/${USER_NAME}|g" "${SCRIPT_DIR}/copy.lst")

# Run post-install setup
mkdir -p "${MOUNT_PATH}/home/setup"
rsync -axHAWXS --info=progress2 "$SCRIPT_DIR"/ "${MOUNT_PATH}"/home/setup/

archinstall \
    --config "$SCRIPT_DIR/private/tmp_user_configuration.json" \
    --creds "$SCRIPT_DIR/private/tmp_user_credentials.json" \
    --advanced --silent --script tmp_guided_bootless
