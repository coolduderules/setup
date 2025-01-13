#!/bin/bash
set -euo pipefail

# Validate inputs
if [ "$#" -gt 1 ]; then
    echo "Usage: $0 [config_file]"
    exit 1
fi

# Check root privileges
if [ $EUID != 0 ]; then
    if [ "$PWD" != "/Users/jason/Github/setup" ]; then
        sudo "$0" "$@"
        exit $?
    fi
fi

# Configuration variables
export CONFIG_FILE="${1:-config.conf}"
export LOG_FILE="/var/log/btrfs_setup.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handler
error_handler() {
    local line_no=$1
    log "Error occurred in line ${line_no}"
    exit 1
}

trap 'error_handler ${LINENO}' ERR

# Load configuration or use defaults
export HOSTNAME=${HOSTNAME:-"jasonet"}
export TIMEZONE=${TIMEZONE:-"America/New_York"}
ROOT_PASSWORD=${ROOT_PASSWORD:-""}
USER_PASSWORD=${USER_PASSWORD:-""}

read -p "Enter the suffix for the disk labels: " suff
export suff
# Add validation for disk labels
if [ -z "$suff" ]; then
    echo "Error: Disk label suffix cannot be empty"
    exit 1
fi

lin="LIN$suff"
esp="ESP$suff"
umount -R "/dev/disk/by-label/$esp" "/dev/disk/by-label/$lin" >> /dev/null 2>&1 || :
umount -R "LABEL=$esp" >> /dev/null 2>&1 || :
umount -R "LABEL=$lin" >> /dev/null 2>&1 || :
umount -R /mnt/* >> /dev/null 2>&1 || :
umount -R "/dev/disk/by-label/$esp" "/dev/disk/by-label/$lin" > /dev/null 2>&1 || :
umount -R /mnt > /dev/null 2>&1 || :
umount -Rf /mnt > /dev/null 2>&1 || :
rm -rf /mnt/* > /dev/null 2>&1 || :
echo "$lin:$esp"
umount "/dev/disk/by-label/$lin" || :
btr=`blkid -o value -s TYPE "/dev/disk/by-label/$lin" | grep btrfs || :`
echo "$btr"
# Fix syntax error in btrfs check
if [ -n "$btr" ]; then
    echo 'already formatted as btrfs'
else
    echo -e 'anything mounted on /mnt will show here \n\n'
    mount | grep mnt || :

    echo -e "\n press any key to format LABEL=$lin as btrfs"
    read key

    mkfs.btrfs -L "$lin" -n 32k -f "/dev/disk/by-label/$lin"
fi

mkfs.fat -F 32 -n "$esp" "/dev/disk/by-label/$esp"

mount -o compress=zstd,subvol=/ "/dev/disk/by-label/$lin" /mnt
if ls /mnt; then btrfs sub delete -R /mnt/* || :
fi
cd /mnt
btrfs sub list /mnt | awk '{print $9}' | xargs -I{} btrfs sub delete /mnt/{} || :
rm -rf /mnt/*
rm -rf /mnt/.*
btrfs sub create /mnt/@ /mnt/@home /mnt/@.snapshots /mnt/@setup
umount -R /mnt || :
umount "/dev/disk/by-label/$lin" || :
umount "LABEL=$esp" || :
umount "LABEL=$lin" || :
umount "/dev/disk/by-label/$esp" "/dev/disk/by-label/$lin" || :
umount -R /mnt || :

mount -o noatime,compress=zstd:3,space_cache=v2,discard=async,subvol=@ "/dev/disk/by-label/$lin" /mnt
mount -o noatime,compress=zstd:3,space_cache=v2,discard=async,subvol=@home "/dev/disk/by-label/$lin" --mkdir /mnt/home
mount -o noatime,compress=zstd:3,space_cache=v2,discard=async,subvol=@.snapshots "/dev/disk/by-label/$lin" --mkdir /mnt/.snapshots
mount -o noatime,compress=zstd:3,space_cache=v2,discard=async,subvol=@setup "/dev/disk/by-label/$lin" --mkdir /mnt/home/setup
# mount -o compress=zstd,subvol=@log "/dev/disk/by-label/$lin" --mkdir /mnt/var/log
# mount -o compress=zstd,subvol=@pkg "/dev/disk/by-label/$lin" --mkdir /mnt/var/cache/pacman/pkg
# mount -o compress=zstd,subvol=@srv "/dev/disk/by-label/$lin" --mkdir /mnt/srv
# mount -o compress=zstd,subvol=@tmp "/dev/disk/by-label/$lin" --mkdir /mnt/tmp
mount "/dev/disk/by-label/$esp" --mkdir /mnt/boot

#chattr +C /mnt/var/log
#chattr +C /mnt/tmp

# Add better error messages for pacstrap
# curl -q "https://setup.jasonet.cc/pkg.lst" | pacstrap -K -P /mnt - || {

cat /home/jason/branch/pkg.lst | pacstrap -K -P /mnt - || {
    log "Error: Package installation failed: $?"
    exit 1
}
genfstab -L /mnt | grep -ve 'machines\|portables' >> /mnt/etc/fstab
mkdir -p /mnt/home/setup
touch /mnt/home/setup/setup.sh
# System optimization
sed -i '/MAKEFLAGS/c\MAKEFLAGS="-j\$(nproc)"' /mnt/etc/makepkg.conf
sed -i 's/ debug / !debug /' /mnt/etc/makepkg.conf

# Secure password handling
if [ -z "$ROOT_PASSWORD" ]; then
    read -s -p "Enter root password: " ROOT_PASSWORD
    echo
    export ROOT_PASSWORD

fi

if [ -z "$USER_PASSWORD" ]; then
    read -s -p "Enter user password: " USER_PASSWORD
    echo
    export USER_PASSWORD
fi
rsync -axHAWXS --info=progress2 /home/jason/branch/ /mnt/home/setup/

chmod +x /mnt/home/setup/setup.sh || :
log "Starting arch-chroot installation..." || :
arch-chroot /mnt /bin/bash /home/setup/setup.sh || :
# Add desktop environment setup
#cp /home/jason/Github/setup/de-setup.sh /mnt/home/setup/
arch-chroot /mnt /bin/bash /home/setup/de-setup.sh || :
log "Desktop environment setup completed" || :
log "Installation completed successfully" || :
exit 0
