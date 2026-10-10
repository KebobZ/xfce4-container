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
