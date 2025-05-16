#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SCRIPT_DIR

# Source common libraries
# shellcheck source=../lib/usage.sh
source "$SCRIPT_DIR/lib/usage.sh"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# Initialize environment
parse_args "$@"
init_script "$@"

# Generate configs
generate_install_files "$SCRIPT_DIR" || exit 1

# Copy installation files
rsync -axHAWXS --info=progress2 "$SCRIPT_DIR/private/tmp_guided_bootless.py" \
    /usr/lib/python3.13/site-packages/archinstall/scripts/ || exit 1
