#!/usr/bin/env bash
# Let unprivileged user namespaces run on this host, so Chrome's sandbox can start inside the
# desktop container. Ubuntu's AppArmor restriction (apparmor_restrict_unprivileged_userns=1)
# blocks them for unconfined processes, and the container cannot lift it alone.
#
# This is a host-wide weakening of a hardening default. Revert with:
#   sudo rm /etc/sysctl.d/60-xfce4-container-userns.conf
#   sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=1
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo $0" >&2
    exit 1
fi

KEY=kernel.apparmor_restrict_unprivileged_userns
CONF=/etc/sysctl.d/60-xfce4-container-userns.conf
OLD_CONF=/etc/sysctl.d/60-arch-desktop-userns.conf   # written by an earlier project

if [ ! -e "/proc/sys/${KEY//./\/}" ]; then
    echo "$KEY is not present on this kernel. Nothing to change."
    exit 0
fi

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
printf '# Managed by xfce4-container host/allow-userns.sh.\n%s = 0\n' "$KEY" > "$TMP"

CHANGED=0
if ! cmp -s "$TMP" "$CONF" 2>/dev/null; then
    install -m 644 "$TMP" "$CONF"
    CHANGED=1
fi
if [ -e "$OLD_CONF" ]; then
    rm -f "$OLD_CONF"
    CHANGED=1
fi

if [ "$(cat "/proc/sys/${KEY//./\/}")" != 0 ] || [ "$CHANGED" = 1 ]; then
    sysctl -q -p "$CONF"
fi

test "$(cat "/proc/sys/${KEY//./\/}")" = 0
echo "$KEY = 0 (user namespaces allowed on this host)."
