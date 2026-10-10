#!/usr/bin/env bash
# Packages and the unprivileged desktop user. Run inside the container as root:
#   sudo incus exec xfce -- bash /root/xfce4-container/container/bootstrap.sh
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get -y full-upgrade

apt-get install -y --no-install-recommends \
    ca-certificates curl wget git sudo xz-utils iproute2 \
    dbus-user-session dbus-x11 dconf-cli dconf-gsettings-backend \
    ffmpeg fontconfig fonts-inter fonts-jetbrains-mono fonts-noto-color-emoji \
    plank tigervnc-standalone-server tigervnc-tools \
    x11-utils x11-xserver-utils xdotool \
    xfce4 xfce4-terminal \
    docker.io docker-compose-v2 docker-buildx

rm -rf /var/lib/apt/lists/*

# Desktop user. Sudo is handled by desktop-sudo.sh, off unless DESKTOP_SUDO=yes.
if ! id -u desktop >/dev/null 2>&1; then
    useradd -m -s /bin/bash desktop
fi

# Keep the user manager running with no login session, so the desktop starts at boot.
loginctl enable-linger desktop

echo "desktop UID: $(id -u desktop)"
