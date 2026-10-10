#!/usr/bin/env bash
# Give the desktop user passwordless sudo inside the container, or take it away.
# Run as root inside the container. build.sh passes "yes" when DESKTOP_SUDO=yes.
#
# Anything running as the desktop user, including Chrome, can then become root in the
# container. The container itself stays unprivileged.
set -euo pipefail

USER_NAME=desktop
SUDOERS=/etc/sudoers.d/desktop
ENABLE=${1:-no}

if [ "$ENABLE" != yes ]; then
    rm -f "$SUDOERS"
    echo "Desktop sudo is off."
    exit 0
fi

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$USER_NAME" > "$TMP"
visudo -cf "$TMP" >/dev/null
install -m 440 "$TMP" "$SUDOERS"

echo "Desktop sudo is on (passwordless)."
