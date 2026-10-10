#!/usr/bin/env bash
# Install the desktop look, the Chrome launcher, and the VNC and session user services,
# then start them. Run inside the container as root, after bootstrap.sh, theme.sh, and
# chrome-install.sh:
#   sudo incus exec xfce -- bash /root/xfce4-container/container/desktop-setup.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
USER_NAME=desktop
USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
USER_UID=$(id -u "$USER_NAME")
RUNTIME_DIR="/run/user/$USER_UID"
USER_UNIT_DIR="$USER_HOME/.config/systemd/user"
UNITS=(xfce-vnc.service xfce-session.service)
CHANGED=0

user_systemctl() {
    runuser -u "$USER_NAME" -- env \
        XDG_RUNTIME_DIR="$RUNTIME_DIR" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$RUNTIME_DIR/bus" \
        systemctl --user "$@"
}

# Config files mirror their target paths under container/config/:
#   etc/… and usr/… install to /etc/… and /usr/…
#   home/… installs into the desktop user's home.
install_config() {
    local src rel dst mode
    while IFS= read -r src; do
        rel=${src#"$HERE/config/"}
        mode=644
        case "$rel" in
            home/*) dst="$USER_HOME/${rel#home/}" ;;
            *)
                dst="/$rel"
                case "$rel" in usr/local/bin/*) mode=755 ;; esac
                ;;
        esac
        install -d "$(dirname "$dst")"
        if ! cmp -s "$src" "$dst" 2>/dev/null; then
            install -m "$mode" "$src" "$dst"
            CHANGED=1
        fi
    done < <(find "$HERE/config" -type f)
}

install_config
chown -R "$USER_NAME:$USER_NAME" "$USER_HOME/.config"

# XFCE reads its default panel layout from here.
install -D -m 644 /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml /etc/xdg/xfce4/panel/default.xml

# Chrome launchers always go through the wrapper that sets its flags.
for name in google-chrome-stable chromium chromium-browser; do
    ln -sfn /usr/local/bin/google-chrome "/usr/local/bin/$name"
done
install -d /usr/local/share/applications
sed 's#/usr/bin/google-chrome-stable#/usr/local/bin/google-chrome#g' \
    /usr/share/applications/google-chrome.desktop \
    > /usr/local/share/applications/google-chrome.desktop

dconf update
fc-cache -f >/dev/null

# User units: the VNC display and the XFCE session on it.
install -d -o "$USER_NAME" -g "$USER_NAME" -m 755 "$USER_UNIT_DIR"
for unit in "${UNITS[@]}"; do
    if ! cmp -s "$HERE/systemd/$unit" "$USER_UNIT_DIR/$unit" 2>/dev/null; then
        install -o "$USER_NAME" -g "$USER_NAME" -m 644 "$HERE/systemd/$unit" "$USER_UNIT_DIR/$unit"
        CHANGED=1
    fi
done

# Lingering starts the user manager. Wait for its D-Bus socket before using it.
systemctl start "user@$USER_UID.service"
for _ in $(seq 1 20); do
    [ -S "$RUNTIME_DIR/bus" ] && break
    sleep 1
done
test -S "$RUNTIME_DIR/bus" || { echo "No user bus at $RUNTIME_DIR/bus" >&2; exit 1; }

user_systemctl daemon-reload
user_systemctl enable "${UNITS[@]}"
# Restart only when a file changed, so a rerun does not reset a working desktop.
if [ "$CHANGED" = 1 ]; then
    user_systemctl restart "${UNITS[@]}"
else
    user_systemctl start "${UNITS[@]}"
fi
user_systemctl --no-pager status "${UNITS[@]}" || true

echo "Desktop installed. VNC on 127.0.0.1:5901; the session runs on display :1."
