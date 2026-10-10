#!/usr/bin/env bash
# Optional: publish noVNC through a Cloudflare quick tunnel. Run as root:
#   sudo host/install-quick-tunnel.sh
#
# The tunnel serves 127.0.0.1:6080 at a random https://*.trycloudflare.com URL. Anyone with
# the URL reaches the noVNC login, so host/install-novnc.sh must have run first. The URL
# changes whenever the tunnel restarts. Stop it with: sudo systemctl stop xfce-quick-tunnel
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo $0" >&2
    exit 1
fi

HERE=$(cd "$(dirname "$0")" && pwd)
KEYRING=/usr/share/keyrings/cloudflare-public-v2.gpg
SOURCES=/etc/apt/sources.list.d/cloudflared.list
UNIT=xfce-quick-tunnel.service

# cloudflared comes from Cloudflare's signed apt repository.
if ! command -v cloudflared >/dev/null 2>&1; then
    install -d -m 755 /usr/share/keyrings
    curl -fsSL -o "$KEYRING" https://pkg.cloudflare.com/cloudflare-public-v2.gpg
    echo "deb [signed-by=$KEYRING] https://pkg.cloudflare.com/cloudflared any main" > "$SOURCES"
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq cloudflared
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

# cloudflared prints the URL to its log once the tunnel is up.
URL=""
for _ in $(seq 1 30); do
    URL=$(journalctl -u "$UNIT" --no-pager -o cat 2>/dev/null \
        | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | tail -n 1 || true)
    [ -n "$URL" ] && break
    sleep 2
done

if [ -n "$URL" ]; then
    echo "Quick tunnel URL (noVNC login required): $URL"
else
    echo "No tunnel URL yet. Check: sudo journalctl -u $UNIT" >&2
    exit 1
fi
