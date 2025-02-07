#!/bin/bash
set -eo pipefail

error() { printf "Error: %s\n" "$*" >&2; exit 1; }
status() { printf ">>> %s\n" "$*" >&2; }
cleanup() { [[ -d $MOUNT_PATH ]] && [[ "$?" != 0 ]] && mountpoint -q "$MOUNT_PATH" && umount -R "$MOUNT_PATH" 2>/dev/null; }
mount_subvol() {
    local subvol="$1" mp="$2"
    mp=${mp##/}
    status "Mounting ${subvol} at $MOUNT_PATH/$mp"
    mount -o "$MOUNT_OPTS$subvol" --mkdir "$device" "$MOUNT_PATH/$mp" || error "Failed to mount $subvol"
    ls "${MOUNT_PATH}"
}

if [[ "$EUID" != 0 ]]; then
    exec sudo -E -- "$0" "$@"
    exit 0
fi
command -v dialog >/dev/null || pacman -Sy --noconfirm dialog
command -v btrfs >/dev/null || pacman -Sy --noconfirm btrfs-progs
MOUNT_OPTS="defaults,ssd,noatime,autodefrag,compress-force=zstd:3,discard=async,space_cache=v2,subvol="
MOUNT_PATH="/mnt"

# Source config and handle variable expansion
if [[ -n $1 && -f $1 && -z $2 ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$1"
    set +a
    [[ -n $SUFF ]] && lin="LIN${SUFF}" && esp="ESP${SUFF}"
    shift
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--mount-path)
            MOUNT_PATH=${2:-/mnt}
            shift 2
            ;;
        -h|--help)
            cat <<-EOF
Usage: $0 [config] [-m path] [device]
Mount BTRFS subvolumes from config, device or label.
Config: MOUNT_PATH=, DEVICE=, SUBVOLUMES="subvol=path"
EOF
            exit 0
            ;;
        -*)
            error "Unknown option: $1"
            ;;
        *)
            if [[ -n "${SUFF}" ]]; then
                lin="LIN${SUFF}"
		esp="ESP${SUFF}"
            fi
            shift
            ;;
    esac
done

mkdir -p "$MOUNT_PATH" || error "Cannot create $MOUNT_PATH"
[[ -w $MOUNT_PATH ]] || error "Mount point not writable: $MOUNT_PATH"
trap cleanup EXIT

# Get and mount BTRFS device
if [[ -n $lin ]]; then
    device="/dev/disk/by-label/$lin"
    echo "$device $lin $MOUNT_PATH $SUFF $SUBVOLUMES"
else
    mapfile -t devices < <(
        find /dev -type b -exec bash -c '
            for d; do
                [[ $(blkid -p -o value -s TYPE "$d") == "btrfs" ]] || continue
                echo "$d"
                lsblk -no SIZE,LABEL,FSUSE% "$d" 2>/dev/null
            done' _ {} +
    )
    [[ ${#devices[@]} -gt 0 ]] || error "No BTRFS devices found"

    device=$(dialog --stdout --no-collapse --colors \
                   --title "Device Selection" \
                   --menu "\nSelect partition:\n " 25 80 15 \
                   "${devices[@]/%*/}") || error "No device selected"
fi

# Validate
[[ -b $device && $(blkid -p -o value -s TYPE "$device") == "btrfs" ]] ||
    error "Not a valid BTRFS device: $device"
if [[ -z "$SUBVOLUMES" ]]; then
    mount -o "$MOUNT_OPTS/" "$device" "$MOUNT_PATH" || error "Mount failed"

    # Get subvolumes
    mapfile -t subvols < <(btrfs subvolume list "$MOUNT_PATH" | awk '{print $NF}' | sort)
    [[ ${#subvols[@]} -gt 0 ]] || error "No subvolumes found"

    # Select and mount root
    root_subvol=$(printf '%s\n' "${subvols[@]}" | grep -m1 '^@$') \
        || root_subvol=$(dialog --stdout --title "Root Selection" \
                        --menu "\nSelect root subvolume:\n " 25 80 15 \
                        "${subvols[@]}") || error "No root selected"
    umount -R "${MOUNT_PATH}"
else
    root_subvol="@"
    status "Mounting root subvolume: $root_subvol from device: $device at $MOUNT_PATH"
    mount -o "$MOUNT_OPTS$root_subvol" "$device" "$MOUNT_PATH" \
        || error "Failed to mount root subvolume"
fi
#Mount remaining subvolumes
if [[ -n $SUBVOLUMES ]]; then
    while IFS='=' read -r subvol mp; do
        [[ -z $subvol || $subvol == \#* || $subvol == "$root_subvol" ]] && continue
        mount_subvol "$subvol" "$mp"
    done < <(echo "$SUBVOLUMES" | tr ' ' '\n')
elif [[ -f "$MOUNT_PATH/etc/fstab" ]]; then
    while read -r _ mp fs opts _; do
        [[ $fs != "btrfs" || $opts != *"subvol="* ]] && continue
        subvol=${opts#*subvol=}; subvol=${subvol%%,*}
        [[ $subvol != "$root_subvol" ]] && mount_subvol "$subvol" "$mp"
    done < "$MOUNT_PATH/etc/fstab"
fi
status "Subvolumes successfully mounted"
if [[ -b "/dev/disk/by-label/$esp" ]]; then
    mount -o defaults,noatime "/dev/disk/by-label/$esp" "$MOUNT_PATH"/boot && status "Successfully mounted /dev/disk/by-label/$esp at $MOUNT_PATH/boot" || status "Could not mount /dev/disk/by-label/$esp at $MOUNT_PATH/boot"
else
    status "Could not find ESP at /dev/disk/by-label/$esp, mount ESP partition manually."
fi
