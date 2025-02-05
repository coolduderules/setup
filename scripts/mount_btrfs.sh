#!/bin/bash
set -eo pipefail

error() { printf "Error: %s\n" "$*" >&2; exit 1; }

cleanup() { [[ -d $MOUNT_PATH ]] && mountpoint -q "$MOUNT_PATH" && umount -R "$MOUNT_PATH" 2>/dev/null; }
mount_subvolumes() {
	echo "Cleaning up mount path: $MOUNT_PATH"
	[[ -d $MOUNT_PATH ]] && mountpoint -q "$MOUNT_PATH" &&
	umount -R "$MOUNT_PATH" 2>/dev/null || true
	rm -rf "${MOUNT_PATH:-/mnt}"/* "${MOUNT_PATH:-/mnt}"/.* || :
	ecbo "Mounting root subvolume (@) at $MOUNT_PATH"
    mount --mkdir -o "defaults,ssd,noatime,autodefrag,compress-force=zstd:3,discard=async,space_cache=v2,commit=120,subvol=@" \
        "/dev/disk/by-label/${lin}" "$MOUNT_PATH" || return 1

    # Sort and mount other subvolumes by mountpoint depth
    echo "$SUBVOLUMES" | grep -v '^#' | grep -v '@=/' | sort -t'/' -k2 \
        | while IFS='=' read -r subvol mountpoint; do
            [[ -z $subvol || $subvol =~ ^[[:space:]]*# ]] && continue
			subvol=${subvol// /}
            mountpoint=${mountpoint// /}
			echo "Mounting subvolume $subvol to $MOUNT_PATH$mountpoint"
            mount --mkdir -o "defaults,ssd,noatime,autodefrag,compress-force=zstd:3,discard=async,space_cache=v2,commit=120,subvol=$subvol" \
                "/dev/disk/by-label/${lin}" "$MOUNT_PATH$mountpoint" || {
                return $?
            }
        done
	mount -o defaults,noatime "/dev/disk/by-label/${esp}" "${MOUNT_PATH}/boot" || return 1
}

if [[ $EUID  != 0 ]]; then
	echo "Script must be run as root, attempting to elevate"
	exec sudo -E -- "$0" "$@"
	exit 1
fi
command -v dialog >/dev/null || pacman -Sy --noconfirm dialog
command -v btrfs >/dev/null || pacman -Sy --noconfirm btrfs-progs

# Source config and handle variable expansion
if [[ -n $1 && -f $1 && -z $2 ]]; then
	# shellcheck disable=SC1090
	source "$1"
	[[ -n $SUFF ]] && lin="LIN${SUFF}" && esp="ESP${SUFF}"
	shift
fi

while [[ $# -gt 0 ]]; do
	case "$1" in
		-m|--mount-path) MOUNT_PATH=${2:-/mnt}; shift 2 ;;
		-h|--help) cat <<EOF
Mount BTRFS subvolumes from config, device or label.

Usage: $0 [config] [-m path] [device]

Config example: ### ESP and root partitions are named ESP(SUFF) and LIN(SUFF)
Just because I automate a lot of installs and devices it removes any chance of mix-ups
feel free to change it to your liking ###

MOUNT_PATH=''
SUFF=''
SUBVOLUMES='
@=/
@home=/home
@log=/var/log
'
EOF
			exit 0 ;;
		-*) error "Unknown option: $1" ;;

		*) # shellcheck disable=SC1090
		   [[ -n "${SUFF}" ]] || source "$1" && lin="LIN${SUFF}" && esp="ESP${SUFF}"; shift ;;
	esac
done
[[ -w $MOUNT_PATH ]] || error "Mount point not writable: $MOUNT_PATH"
[[ -n $lin ]] || error "No device specified"
if ! mount_subvolumes; then
	error "Mounting failed with error: $?"
else
	error "Mounting failed"
fi
