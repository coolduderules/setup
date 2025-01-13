#!/bin/bash
echo "DE_SETUP BEGINS HERE"
set -euo pipefail

# Check if running as root
if [ $EUID != 0 ]; then
    sudo "$0" "$@"
    exit $?
fi

# Enable display manager
systemctl enable lightdm
mkdir /etc/lightdm/lightdm.conf.d
# Configure LightDM
cat <<EOF > /etc/lightdm/lightdm.conf.d/20-enable-numlock.conf
[Seat:*]
greeter-setup-script=/usr/bin/numlockx on
EOF

# Configure LightDM
cat <<EOF > /etc/lightdm/lightdm.conf.d/50-sessions.conf
[Seat:*]
session-wrapper=/etc/lightdm/Xsession
user-session=i3
EOF

pacman -U --noconfirm /home/setup/repo/alternatives-1.31-1-x86_64.pkg.tar.zst
# Set default terminal
touch /usr/lib/alternatives/x-terminal-emulator
update-alternatives --set x-terminal-emulator /usr/bin/xfce4-terminal

# Configure default applications
cat <<EOF > /etc/environment
EDITOR=nano
BROWSER=firefox
TERMINAL=xfce4-terminal
MOZ_USE_XINPUT2=1
EOF

# Enable audio
systemctl --user enable pipewire pipewire-pulse wireplumber

# Enable network applet for all users
mkdir -p /etc/xdg/autostart
cat <<EOF > /etc/xdg/autostart/nm-applet.desktop
[Desktop Entry]
Type=Application
Name=Network Manager Applet
Exec=nm-applet
Icon=network-wireless
Comment=Network management
X-GNOME-Autostart-enabled=true
EOF

# Create default i3 config for new users
mkdir -p /etc/skel/.config/i3
cat <<EOF > /etc/skel/.config/i3/config
# i3 config file (v4)
font pango:monospace 8
floating_modifier Mod4
bindsym Mod4+Return exec xfce4-terminal
bindsym Mod4+d exec dmenu_run
bindsym Mod4+Shift+q kill
bindsym Mod4+Shift+e exit
bindsym Mod4+Shift+c reload
bindsym Mod4+Shift+r restart
bindsym Mod4+Left focus left
bindsym Mod4+Right focus right
bindsym Mod4+Up focus up
bindsym Mod4+Down focus down
bindsym Mod4+Shift+Left move left
bindsym Mod4+Shift+Right move right
bindsym Mod4+Shift+Up move up
bindsym Mod4+Shift+Down move down
bindsym Mod4+h split h
bindsym Mod4+v split v
bindsym Mod4+f fullscreen toggle
bindsym Mod4+s layout stacking
bindsym Mod4+w layout tabbed
bindsym Mod4+e layout toggle split
bindsym Mod4+Shift+space floating toggle
bindsym Mod4+space focus mode_toggle
bindsym Mod4+1 workspace 1
bindsym Mod4+2 workspace 2
bindsym Mod4+3 workspace 3
bindsym Mod4+4 workspace 4
bindsym Mod4+Shift+1 move container to workspace 1
bindsym Mod4+Shift+2 move container to workspace 2
bindsym Mod4+Shift+3 move container to workspace 3
bindsym Mod4+Shift+4 move container to workspace 4

# Autostart applications
exec --no-startup-id nm-applet
exec --no-startup-id udiskie -t
EOF

# Set up Xresources defaults
cat <<EOF > /etc/skel/.Xresources
Xft.dpi: 96
Xft.antialias: true
Xft.hinting: true
Xft.rgba: rgb
Xft.autohint: false
Xft.hintstyle: hintslight
Xft.lcdfilter: lcddefault
EOF

# Configure X11 forwarding defaults
cat <<EOF > /etc/X11/Xwrapper.config
allowed_users=anybody
needs_root_rights=yes
EOF

# Enable bitmap fonts for X11
rm -f /etc/fonts/conf.d/70-no-bitmaps.conf
fc-cache -f

# Additional security hardening
#cat <<EOF > /etc/sysctl.d/99-security.conf
#net.ipv4.tcp_syncookies=1
#net.ipv4.tcp_rfc1337=1
#net.ipv4.conf.all.rp_filter=1
#net.ipv4.conf.default.rp_filter=1
#EOF

# Set default shell for new users
sed -i 's|SHELL=/bin/bash|SHELL=/bin/zsh|' /etc/default/useradd
