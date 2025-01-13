#!/bin/bash
set -euo pipefail

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

# System configuration
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc

# Locale setup
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf
locale-gen

# Network setup
echo "${HOSTNAME}" > /etc/hostname
cat <<- EOF > /etc/hosts
127.0.0.1    localhost
::1          localhost
127.0.0.1    ${HOSTNAME}
EOF



# Secure password setting
echo "${ROOT_PASSWORD}" | passwd --stdin root
useradd -m -G wheel -s /bin/bash jason
echo "${USER_PASSWORD}" | passwd --stdin jason
sed -i 's/\# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers


for user in /home/*; do
    username=$(basename "$user");
    echo "UPDATING DIRS $user $username"
    if [[ -d "$username" ]] -a [[ "$username" != "setup" ]]; then
        sudo -u "$username" /usr/bin/xdg-user-dirs-update
    fi
done

# Configure SSH for X11 forwarding
sed -i 's/#X11Forwarding no/X11Forwarding yes/' /etc/ssh/sshd_config
sed -i 's/#X11UseLocalhost yes/X11UseLocalhost no/' /etc/ssh/sshd_config


systemctl enable NetworkManager sshd cockpit.socket grub-btrfsd
sudo -u jason systemctl --user enable pipewire pipewire-pulse wireplumber
timedatectl set-ntp true
sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
grub-install --efi-directory=/boot --boot-directory=/boot --removable
grub-mkconfig -o /boot/grub/grub.cfg
sudo -u jason git config --global user.name "coolduderules"
sudo -u jason git config --global user.email "masterofpi3.14@gmail.com"
exit 0