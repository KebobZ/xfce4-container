#!/usr/bin/env bash
# Resource limits for the desktop container and the host gateway. Run as root:
#   sudo host/resource-policy.sh
#
# Override defaults with env vars, for example:
#   DISK_SIZE=80GiB PID_LIMIT=8192 sudo host/resource-policy.sh
#
# Deliberately sets no memory cap on the container.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo $0" >&2
    exit 1
fi

CT="${CT:-xfce}"
PID_LIMIT="${PID_LIMIT:-4096}"
DISK_SIZE="${DISK_SIZE:-}"                    # empty = leave the root disk unlimited
NOVNC_MEMORY_LOW="${NOVNC_MEMORY_LOW:-128M}"

# Fork-bomb protection inside the container.
incus config set "$CT" limits.processes "$PID_LIMIT"

if [ -n "$DISK_SIZE" ]; then
    # Inherited root devices must be overridden locally before they can be changed.
    if incus config device show "$CT" | grep -q '^root:'; then
        incus config device set "$CT" root size="$DISK_SIZE"
    else
        incus config device override "$CT" root size="$DISK_SIZE"
    fi
fi

# Soft reclaim protection for the gateway. MemoryLow is best-effort, not a guarantee.
systemctl set-property xfce-novnc.service MemoryLow="$NOVNC_MEMORY_LOW"

echo "Applied: $CT limits.processes=$PID_LIMIT, MemoryLow novnc=$NOVNC_MEMORY_LOW${DISK_SIZE:+, root size=$DISK_SIZE}"
