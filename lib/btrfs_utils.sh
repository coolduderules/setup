#!/bin/bash
# Check BTRFS tools
check_btrfs_tools() {
    local -r DEPS=(btrfs mkfs.btrfs)
    local missing=()

    for cmd in "${DEPS[@]}"; do
        command -v "$cmd" > /dev/null 2>&1 || missing+=("$cmd")
    done

    if ((${#missing[@]} > 0)); then
        log "Missing required BTRFS tools: ${missing[*]}" "ERROR"
        return 1
    fi
    return 0
}

# Validate environment
check_requirements() {
    check_btrfs_tools || return 1

    local -r required=("MOUNT_PATH" "SUBVOLUMES" "SUFF")
    local missing=()

    for var in "${required[@]}"; do
        [[ -z ${!var:-} ]] && missing+=("$var")
    done

    if ((${#missing[@]} > 0)); then
        log "Missing required variables: ${missing[*]}" "ERROR"
        return 1
    fi
}
if [[ $MOUNT_ONLY == 1 ]]; then
    check_requirements
    exec "$0/../scripts/mount_btrfs.sh" "${CONFIG_FILE}"
    exit 1
fi
# Enhanced subvolume deletion
delete_subvolume() {
    local mount_path="${MOUNT_PATH:-1}"
    local subvol=$2
    local full_path
    local -r max_retries=3

    # Normalize paths
    mount_path=$(realpath "$mount_path")
    full_path="$mount_path/$subvol"

    # Ensure subvolume exists and is actually a subvolume
    if ! btrfs subvolume show "$full_path" &> /dev/null; then
        log "Not a subvolume or doesn't exist: $full_path" "DEBUG"
        return 0
    fi

    log "Attempting to delete subvolume: $full_path" "DEBUG"

    # Ensure subvolume is unmounted
    if mountpoint -q "$full_path"; then
        log "Unmounting subvolume: $full_path" "DEBUG"
        umount -R "$full_path" 2> /dev/null || umount -l -R "$full_path" 2> /dev/null || true
        sleep 1
    fi

    # Retry deletion with better error handling
    for ((retry = 1; retry <= max_retries; retry++)); do
        if btrfs subvolume delete -C -R "$full_path" 2> /dev/null; then
            log "Successfully deleted subvolume: $full_path" "DEBUG"
            return 0
        fi
        log "Retry $retry/$max_retries deleting subvolume: $full_path" "DEBUG"
    done

    log "Failed to delete subvolume after $max_retries attempts: $full_path" "ERROR"
}

# Initial mount for subvolume creation
mount_btrfs_root() {
    mount --mkdir -t btrfs -o "defaults,ssd,noatime,autodefrag,compress-force=zstd:3,discard=async,space_cache=v2,commit=120" \
        "/dev/disk/by-label/${lin}" "$MOUNT_PATH" || return 1
}

# Two-phase subvolume recreation
recreate_subvolumes() {
    check_requirements || return 1

    mount_btrfs_root || {
        log "Failed to mount root for subvolume creation" "ERROR"
        return 1
    }

    # Delete existing subvolumes
    btrfs subvolume list -o "$MOUNT_PATH" 2> /dev/null | sort -r | awk '{print $NF}' \
        | while read -r subvol; do
            delete_subvolume "$MOUNT_PATH" "$subvol" || true
        done
    if btrfs subvolume show "$MOUNT_PATH/@" 2> /dev/null; then
        btrfs subvolume sync "$MOUNT_PATH" || true
    fi
    rm -rf "${MOUNT_PATH:?}"/* || :
    mkdir -p /var/lib/{portables,machines} || :
    # Create new subvolumes at root
    echo "$SUBVOLUMES" | while IFS='=' read -r subvol mountpoint; do
        [[ -z $subvol || $subvol =~ ^[[:space:]]*# ]] && continue
        subvol=${subvol// /}
        btrfs subvolume create "$MOUNT_PATH/$subvol" || return 1
    done || {
        umount "$MOUNT_PATH" 2> /dev/null || :
        unmount "${lin}" 2> /dev/null || :
    }

    umount "$MOUNT_PATH" || :
}

# Mount subvolumes in correct locations
mount_subvolumes() {
    cleanup_mounts "$MOUNT_PATH" || return 1
    log "Mounting root subvolume (@)" "DEBUG"
    mount --mkdir -o "defaults,ssd,noatime,autodefrag,compress-force=zstd:3,discard=async,space_cache=v2,commit=120,subvol=@" \
        "/dev/disk/by-label/${lin}" "$MOUNT_PATH" || return 1
    echo "$SUBVOLUMES" | grep -v '^#' | grep -v '@=/' | sort -t'/' -k2 \
        | while IFS='=' read -r subvol mountpoint; do
            [[ -z $subvol || $subvol =~ ^[[:space:]]*# ]] && continue
            subvol=${subvol// /}
            mountpoint=${mountpoint// /}
            mkdir -p "$MOUNT_PATH$mountpoint"
        done || :
    rm -rf "$MOUNT_PATH/var/lib/portables" > /dev/null 2>&1 || :
    rm -rf "$MOUNT_PATH/var/lib/machines" > /dev/null 2>&1 || :
    umount -R "$MOUNT_PATH/var/lib/portables" > /dev/null 2>&1 || :
    umount -R "$MOUNT_PATH/var/lib/machines" > /dev/null 2>&1 || : 
    btrfs sub delete -C "$MOUNT_PATH/var/lib/portables" > /dev/null 2>&1 || :
    btrfs sub delete -C "$MOUNT_PATH/var/lib/machines" > /dev/null 2>&1 || :
    rm -rf "$MOUNT_PATH/var/lib/portables" > /dev/null 2>&1 || :
    rm -rf "$MOUNT_PATH/var/lib/machines" > /dev/null 2>&1 || : 
    mkdir -p "$MOUNT_PATH/var/lib/machines" > /dev/null 2>&1 || :
    mkdir -p "$MOUNT_PATH/var/lib/portables" > /dev/null 2>&1 || :

    # Sort and mount other subvolumes by mountpoint depth
    echo "$SUBVOLUMES" | grep -v '^#' | grep -v '@=/' | sort -t'/' -k2 \
        | while IFS='=' read -r subvol mountpoint; do
            [[ -z $subvol || $subvol =~ ^[[:space:]]*# ]] && continue

            # Clean up subvol/mountpoint
            subvol=${subvol// /}
            mountpoint=${mountpoint// /}

            log "Mounting subvolume $subvol to $MOUNT_PATH$mountpoint" "DEBUG"
            mount --mkdir -o "defaults,ssd,noatime,autodefrag,compress-force=zstd:3,discard=async,space_cache=v2,commit=120,subvol=$subvol" \
                "/dev/disk/by-label/${lin}" "$MOUNT_PATH$mountpoint" || {
                return $?
            }
        done
}

# fstab generation
generate_fstab() {

    printf "LABEL=ESP%s    /boot    vfat    defaults,noatime    0 2\n" "$SUFF"

    echo "$SUBVOLUMES" | while IFS='=' read -r subvol mountpoint; do
        [[ -z $subvol || $subvol =~ ^[[:space:]]*# || $subvol =~ ^\.snapshots$ ]] && continue
        printf "LABEL=LIN%s    %s    btrfs    defaults,ssd,noatime,autodefrag,compress-force=zstd:3,discard=async,space_cache=v2,commit=120,subvol=%s    0 0\n" \
            "$SUFF" "${mountpoint// /}" "${subvol// /}"
    done | sort -k2,2
}

# Setup filesystems and subvolumes
mount_and_setup_subvolumes() {

    local lin="LIN${SUFF}"
    local esp="ESP${SUFF}"
    if ! blkid -o value -s TYPE "/dev/disk/by-label/${lin}" | grep -q btrfs; then
        log "Formatting ${lin} as BTRFS"
        mkfs.btrfs -L "${lin}" -n 32k -f "/dev/disk/by-label/${lin}" || return 1
    fi

    cleanup_mounts "$MOUNT_PATH" || :
    lsof "$MOUNT_PATH" | grep -v 'COMMAND' | awk '{print $2}' | xargs kill -9 || :
    umount -R "$MOUNT_PATH" || umount -l -R "$MOUNT_PATH" || :

    if [[ $RECREATE_SUBVOLS == 1 ]]; then
        recreate_subvolumes
    fi
    
    cleanup_mounts
    mount_btrfs_root
    mount_subvolumes
    echo "creating EFI filesystem"
    mkfs.fat -F 32 -n "${esp}" "/dev/disk/by-label/${esp}"
    mount --mkdir -o "defaults,noatime" "/dev/disk/by-label/${esp}" "$MOUNT_PATH/boot" || return 1
}

export -f recreate_subvolumes mount_and_setup_subvolumes mount_subvolumes generate_fstab
