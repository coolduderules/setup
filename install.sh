#!/bin/bash

# Setup core environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR

# Source core libraries in dependency order
source "$SCRIPT_DIR/lib/usage.sh"
source "$SCRIPT_DIR/lib/common.sh"

# Initialize environment first
parse_args "$@"
init_script "$@"

# Now source the rest that need initialized variables
source "$SCRIPT_DIR/lib/btrfs_utils.sh"
source "$SCRIPT_DIR/lib/install_utils.sh"

# Main installation logic
main() {
    local status=0

    # Phase 1: Preparation
    log "Phase 1: Preparing installation"
    "$SCRIPT_DIR/scripts/prepare.sh" || return $?

    # Phase 2: Filesystem Setup
    log "Phase 2: Setting up filesystems"
    mount_and_setup_subvolumes || return $?

    # Phase 3: System Installation
    log "Phase 3: Bootstrapping system"
    "$SCRIPT_DIR/scripts/bootstrap.sh" || return $?

    # Phase 4: Post-Install Setup
    log "Phase 4: Running post-installation tasks"
    arch-chroot "${MOUNT_PATH}" "/home/setup/private/scripts/post.sh" || return $?

    return 0
}

# Execute installation
if main; then
    log "Installation completed successfully"
    exit 0
else
    status=$?
    log "Installation failed with status $status" "ERROR"
    exit $status
fi
