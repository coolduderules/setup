#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${SCRIPT_DIR}"/scripts/config.conf
#shellcheck disable=SC1090
source "${CONFIG_FILE}"
echo "SCRIPT_DIR=${SCRIPT_DIR}"
echo "CONFIG_FILE=${CONFIG_FILE}"
# User configuration
groupadd -r cockpit-wsinstance || :
groupadd -r chrome-remote-desktop || :
usermod -aG chrome-remote-desktop "${USER_NAME}" || :
sed -i 's/#PACMAN_AUTH=()/PACMAN_AUTH=(echo -ne \"'"${USER_PASSWORD}"'\\n\" | sudo -S )/' /etc/sudoers || :
pacman -Syy

# System services
if [[ -r "$SCRIPT_DIR/pkg.lst" ]]; then
    while read -r pkg; do
        pacman -S --needed --noconfirm "${pkg}" || :
        systemctl enable "${pkg}.service" 2> /dev/null || systemctl enable "${pkg}.socket" 2> /dev/null || :
    done < "$SCRIPT_DIR/pkg.lst"
fi
for pkg in $(find "${SCRIPT_DIR}/repo/" | grep 'chaotic\|apple\|chrome'); do
    pacman -U --needed --noconfirm "$pkg"
done
systemctl enable chrome-remote-desktop@"${USER_NAME}".service
systemctl enable sshd.service cockpit.socket || :
sed -i 's/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers
#timedatectl set-ntp true
sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
grub-install --efi-directory=/boot --boot-directory=/boot --removable || error_handler ${LINENO} "grub-install" $?
grub-mkconfig -o /boot/grub/grub.cfg || error_handler ${LINENO} "grub-mkconfig" $?
generate_fstab >> /etc/fstab
log "Setup completed successfully"
rsync -axHAWXS --info=progress2 /home/setup/.private/filesystem/ "${MOUNT_PATH}"/
chown -R root / || :
chown -R "${USER_NAME}" "/home/" || :
cd "${SCRIPT_DIR}"/.private/filesystem/home/jason/HyDE/Scripts || :
sudo -u "${USER_NAME}" /home/"${USER_NAME}"/HyDE/Scripts/install.sh -drs || :