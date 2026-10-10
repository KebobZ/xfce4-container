#!/usr/bin/env bash
# Install Google Chrome from Google's .deb. Run inside the container as root.
# The launcher wrapper and menu entry are set up by desktop-setup.sh.
set -euo pipefail

DEB_URL=https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb

if dpkg -s google-chrome-stable >/dev/null 2>&1; then
    echo "google-chrome-stable is already installed."
else
    WORK=$(mktemp -d)
    trap 'rm -rf "$WORK"' EXIT
    wget -q -O "$WORK/chrome.deb" "$DEB_URL"
    # bootstrap.sh clears the package lists to keep the image small, so refresh them here.
    apt-get update
    # apt resolves the dependencies; a local .deb path needs an absolute name.
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$WORK/chrome.deb"
fi

/opt/google/chrome/google-chrome --version

# Headless run as the desktop user, with the sandbox on. Fails when the sandbox cannot start.
OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT
if runuser -u desktop -- timeout 90 /opt/google/chrome/google-chrome \
    --headless=new --disable-gpu --no-first-run --dump-dom about:blank >"$OUT" 2>&1; then
    echo "Chrome sandbox works for the desktop user."
else
    echo "Chrome failed to start with its sandbox for the desktop user:" >&2
    tail -n 20 "$OUT" >&2
    exit 1
fi
