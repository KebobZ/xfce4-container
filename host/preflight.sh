#!/usr/bin/env bash
# Read-only host checks. Changes nothing.
set -euo pipefail

echo "== Ubuntu release"
. /etc/os-release
echo "$PRETTY_NAME"

echo "== cgroup v2 controllers"
if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
    cat /sys/fs/cgroup/cgroup.controllers
else
    echo "WARNING: cgroup v2 not detected" >&2
fi

echo "== Subordinate ID ranges for root"
if grep -q '^root:' /etc/subuid && grep -q '^root:' /etc/subgid; then
    grep '^root:' /etc/subuid /etc/subgid
else
    echo "WARNING: missing root range in /etc/subuid or /etc/subgid" >&2
    echo "Fix: sudo usermod -v 1000000-1999999 -w 1000000-1999999 root" >&2
    echo "Then re-run ./build.sh." >&2
    exit 1
fi
