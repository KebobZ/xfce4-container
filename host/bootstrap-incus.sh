#!/usr/bin/env bash
# Install host packages, initialize Incus, and launch the Ubuntu desktop container.
# Idempotent: every step checks whether it already happened.
#
# If you want a custom storage pool, run `sudo incus admin init` by hand first.
# Otherwise this runs `incus admin init --minimal` (dir-backed pool and NAT bridge).
set -euo pipefail

CT="${CT:-xfce}"
NET="${NET:-incusbr0}"
IMAGE="${IMAGE:-images:ubuntu/26.04}"

wait_for_ipv4() {
    local addrs
    for _ in $(seq 1 30); do
        addrs=$(sudo incus list "$CT" --format csv -c 4)
        if grep -Eq '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' <<<"$addrs"; then
            return 0
        fi
        sleep 2
    done
    return 1
}

if ! dpkg -s incus websockify novnc >/dev/null 2>&1; then
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y incus websockify novnc
fi

sudo systemctl enable --now incus.service

if [ -z "$(sudo incus storage list --format csv)" ]; then
    sudo incus admin init --minimal
fi

if sudo incus info "$CT" >/dev/null 2>&1; then
    echo "Container '$CT' already exists; skipping launch."
else
    # No limits.memory, limits.cpu, or security.privileged on purpose.
    sudo incus launch "$IMAGE" "$CT" \
        -c boot.autostart=true \
        -c security.nesting=true \
        -c security.syscalls.intercept.mknod=true \
        -c security.syscalls.intercept.setxattr=true
fi

# With UFW active, its default policy rejects incoming and routed traffic. That blocks
# DHCP and DNS from the Incus bridge. Allow the bridge explicitly. Rules are idempotent.
UFW_STATE=$(sudo ufw status 2>/dev/null || true)
if grep -q '^Status: active' <<<"$UFW_STATE"; then
    sudo ufw allow in on "$NET"
    sudo ufw route allow in on "$NET"
    sudo ufw route allow out on "$NET"
fi

if ! wait_for_ipv4; then
    echo "Container $CT has no IPv4 address yet; restarting it to retry DHCP."
    sudo incus restart "$CT"
    if ! wait_for_ipv4; then
        echo "Container $CT still has no IPv4 address. Check UFW and dnsmasq for $NET." >&2
        exit 1
    fi
fi
