#!/usr/bin/env bash
# Host side of the desktop: a loopback port forward into the container, the login for
# the browser, and the noVNC gateway service. Run as root (build.sh calls it):
#   sudo host/install-novnc.sh
#
# The browser reaches noVNC only through 127.0.0.1:6080. websockify asks for HTTP Basic
# auth, then forwards to 127.0.0.1:5901 on the host, which an Incus proxy device connects
# to the desktop's VNC server inside the container.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo $0" >&2
    exit 1
fi

HERE=$(cd "$(dirname "$0")" && pwd)
CT="${CT:-xfce}"
DIR=/etc/xfce4-container
ENV_FILE="$DIR/auth.env"
USERNAME=desktop
UNIT=xfce-novnc.service

# The login is created once. Re-running keeps it.
install -d -o root -g root -m 700 "$DIR"
if [ ! -s "$ENV_FILE" ]; then
    PASSWORD=$(openssl rand -hex 16)
    (umask 077 && printf 'NOVNC_AUTH=%s:%s\n' "$USERNAME" "$PASSWORD" > "$ENV_FILE")
    echo "Created the noVNC login in $ENV_FILE."
fi

# Forward host loopback port 5901 to the VNC server on the container's loopback.
if ! incus config device show "$CT" | grep -q '^vnc:'; then
    incus config device add "$CT" vnc proxy \
        listen=tcp:127.0.0.1:5901 connect=tcp:127.0.0.1:5901 bind=host
fi

UNIT_CHANGED=0
if ! cmp -s "$HERE/systemd/$UNIT" "/etc/systemd/system/$UNIT"; then
    install -o root -g root -m 644 "$HERE/systemd/$UNIT" "/etc/systemd/system/$UNIT"
    UNIT_CHANGED=1
fi

systemctl daemon-reload
systemctl enable --now "$UNIT"
if [ "$UNIT_CHANGED" = 1 ]; then
    systemctl restart "$UNIT"
fi

echo "noVNC username: $USERNAME"
echo "Password: sudo grep NOVNC_AUTH $ENV_FILE"
