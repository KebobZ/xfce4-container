#!/usr/bin/env bash
# Build the whole desktop on this machine with one command. Safe to re-run.
#
#   ./build.sh
#
# Publish the login page at a public trycloudflare.com URL (opt-in):
#   QUICK_TUNNEL=yes ./build.sh
#
# Give the desktop user passwordless sudo in the container (opt-in):
#   DESKTOP_SUDO=yes ./build.sh
# Run again without it to take sudo away.
#
# Each step shows a spinner while it runs. Full output goes to build.log.
# On failure, fix the cause and re-run; finished steps are skipped.
set -euo pipefail

REPO=$(cd "$(dirname "$0")" && pwd)
CT="${CT:-xfce}"
IMAGE="${IMAGE:-images:ubuntu/26.04}"
REMOTE_DIR=/root/xfce4-container
DESKTOP_USER=desktop
LOG="$REPO/build.log"
TOTAL_STAGES=10
STAGE_NO=0
CURRENT_STAGE=start
START_TIME=$SECONDS
TUNNEL_URL=""
SPINNER=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

# ---- output ----------------------------------------------------------------

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    BOLD=$'\033[1m' DIM=$'\033[2m' RED=$'\033[31m' GREEN=$'\033[32m'
    YELLOW=$'\033[33m' CYAN=$'\033[36m' RESET=$'\033[0m'
else
    BOLD= DIM= RED= GREEN= YELLOW= CYAN= RESET=
fi
RULE=$(printf '─%.0s' $(seq 1 64))

info() { printf '  %s·%s %s\n' "$DIM" "$RESET" "$*"; }
warn() { printf '  %s!%s %s\n' "$YELLOW" "$RESET" "$*"; }

stage() {
    STAGE_NO=$((STAGE_NO + 1))
    CURRENT_STAGE="$*"
    echo
    printf '%s%s%d/%d  %s%s\n' "$BOLD" "$CYAN" "$STAGE_NO" "$TOTAL_STAGES" "$*" "$RESET"
    printf '%s%s%s\n' "$DIM" "$RULE" "$RESET"
}

# Runs one step with a spinner. Output goes to build.log. Prints ✓ with the duration,
# or ✗ with the last lines of this step's output.
run_step() {
    local label=$1 started=$SECONDS mark rc=0 i=0 took
    shift
    mark=$(wc -l < "$LOG")
    # Carriage returns from progress bars become newlines, so the log reads line by line.
    if [ -t 1 ]; then
        ( "$@" </dev/null 2>&1 | tr '\r' '\n' >>"$LOG" ) &
        local pid=$!
        while kill -0 "$pid" 2>/dev/null; do
            printf '\r  %s%s%s %s\033[K' "$CYAN" "${SPINNER[i % ${#SPINNER[@]}]}" "$RESET" "$label"
            i=$((i + 1))
            sleep 0.1
        done
        wait "$pid" || rc=$?
        printf '\r\033[K'
    else
        printf '  … %s\n' "$label"
        ( "$@" </dev/null 2>&1 | tr '\r' '\n' >>"$LOG" ) || rc=$?
    fi

    took=$((SECONDS - started))
    if [ "$rc" -eq 0 ]; then
        printf '  %s✓%s %s %s%ss%s\n' "$GREEN" "$RESET" "$label" "$DIM" "$took" "$RESET"
    else
        printf '  %s✗%s %s %s(exit %s)%s\n' "$RED" "$RESET" "$label" "$DIM" "$rc" "$RESET"
        tail -n +"$((mark + 1))" "$LOG" | tail -n 20 | sed "s/^/    ${DIM}│${RESET} /"
        return "$rc"
    fi
}

on_error() {
    echo >&2
    printf '%s%s✗ Build stopped during: %s%s\n' "$BOLD" "$RED" "$CURRENT_STAGE" "$RESET" >&2
    printf '  Full output: %s\n' "$LOG" >&2
    printf '  Fix the cause and run ./build.sh again. Finished steps are skipped.\n' >&2
}
trap on_error ERR

# ---- helpers ---------------------------------------------------------------

incus_ct() {
    sudo incus exec "$CT" -- "$@"
}

user_systemctl() {
    local runtime="/run/user/$DESKTOP_UID"
    incus_ct runuser -u "$DESKTOP_USER" -- env \
        XDG_RUNTIME_DIR="$runtime" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime/bus" \
        systemctl --user "$@"
}

fix_subuid() {
    sudo usermod -v 1000000-1999999 -w 1000000-1999999 root
    if systemctl is-active --quiet incus.service; then
        sudo systemctl restart incus.service
    fi
}

wait_for_container() {
    local state
    for _ in $(seq 1 90); do
        state=$(incus_ct systemctl is-system-running 2>/dev/null || true)
        case "$state" in
            running|degraded) return 0 ;;
        esac
        sleep 2
    done
    echo "Container $CT did not finish booting." >&2
    return 1
}

wait_for_network() {
    for _ in $(seq 1 60); do
        if incus_ct getent hosts archive.ubuntu.com >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    echo "Container $CT cannot resolve DNS names yet." >&2
    return 1
}

push_container_dir() {
    incus_ct mkdir -p "$REMOTE_DIR/container"
    local f
    while IFS= read -r f; do
        sudo incus file push --create-dirs "$REPO/$f" "$CT$REMOTE_DIR/$f"
    done < <(cd "$REPO" && find container -type f)
}

# Waits until the VNC port and the XFCE session are both up. On failure, writes the
# unit status and journal to the log.
wait_for_desktop() {
    DESKTOP_UID=$(incus_ct id -u "$DESKTOP_USER")
    for _ in $(seq 1 30); do
        if incus_ct test -S /tmp/.X11-unix/X1 && incus_ct ss -ltn | grep -q '127.0.0.1:5901'; then
            return 0
        fi
        # The session can start and then exit, so stop early once its unit has stopped.
        user_systemctl is-active --quiet xfce-session.service || break
        sleep 1
    done
    {
        user_systemctl --no-pager status xfce-vnc.service xfce-session.service || true
        incus_ct runuser -u "$DESKTOP_USER" -- env XDG_RUNTIME_DIR="/run/user/$DESKTOP_UID" \
            journalctl --user --no-pager -n 80 || true
    } >>"$LOG" 2>&1
    echo "The XFCE session did not stay up on display :1." >&2
    return 1
}

# Checks that the gateway and VNC proxy listen on loopback only.
check_loopback() {
    local listen="" port
    for _ in $(seq 1 30); do
        listen=$(ss -ltn)
        if grep -q '127.0.0.1:6080' <<<"$listen" && grep -q '127.0.0.1:5901' <<<"$listen"; then
            break
        fi
        sleep 2
    done
    for port in 5901 6080; do
        if ! grep -q "127.0.0.1:$port" <<<"$listen"; then
            echo "Port $port is not listening on 127.0.0.1." >&2
            return 1
        fi
    done
    if grep -Eq '(0\.0\.0\.0|\[::\]|\*):(5901|6080)' <<<"$listen"; then
        echo "The VNC proxy or noVNC is listening beyond loopback. Refusing to continue." >&2
        return 1
    fi
}

# ---- run -------------------------------------------------------------------

: >"$LOG"

echo
printf '%s  xfce4-container%s\n' "$BOLD" "$RESET"
printf '  %s%s · container %s · XFCE on :1 · noVNC on 127.0.0.1:6080%s\n' \
    "$DIM" "$IMAGE" "$CT" "$RESET"

stage "Host checks"
info "Asking for sudo once, so the steps below run unattended."
sudo -v
run_step "Preflight" "$REPO/host/preflight.sh" || true
if ! grep -q '^root:' /etc/subuid || ! grep -q '^root:' /etc/subgid; then
    run_step "Root subordinate ID range for Incus" fix_subuid
fi

stage "Host packages and container"
run_step "Install host packages and launch container '$CT'" \
    env CT="$CT" IMAGE="$IMAGE" "$REPO/host/bootstrap-incus.sh"
run_step "Wait for the container to boot" wait_for_container
run_step "Wait for container networking" wait_for_network

stage "Container packages and desktop user"
run_step "Copy project into the container" push_container_dir
run_step "Install XFCE, TigerVNC, Docker, and fonts" \
    incus_ct bash "$REMOTE_DIR/container/bootstrap.sh"

stage "WhiteSur theme and wallpaper"
run_step "Fetch and install WhiteSur, generate wallpaper" \
    incus_ct bash "$REMOTE_DIR/container/theme.sh"

stage "Google Chrome"
run_step "Allow user namespaces on the host (Chrome sandbox)" sudo "$REPO/host/allow-userns.sh"
run_step "Install Google Chrome and check its sandbox" \
    incus_ct bash "$REMOTE_DIR/container/chrome-install.sh"

stage "Desktop session"
run_step "Install desktop config and user services" \
    incus_ct bash "$REMOTE_DIR/container/desktop-setup.sh"
run_step "Wait for XFCE on :1 and VNC on 127.0.0.1:5901" wait_for_desktop
run_step "Desktop sudo: ${DESKTOP_SUDO:-no}" \
    incus_ct bash "$REMOTE_DIR/container/desktop-sudo.sh" "${DESKTOP_SUDO:-no}"

stage "Login and noVNC gateway"
run_step "Create login and install gateway service" \
    env CT="$CT" sudo -E "$REPO/host/install-novnc.sh"
run_step "Check that the gateway listens on loopback only" check_loopback

stage "Resource limits"
run_step "Apply container and gateway limits" \
    env CT="$CT" sudo -E "$REPO/host/resource-policy.sh"

stage "Docker checks"
run_step "Build, Compose, and published-port test" \
    incus_ct bash "$REMOTE_DIR/container/docker-check.sh"

stage "Public access (opt-in)"
if [ "${QUICK_TUNNEL:-}" = yes ]; then
    run_step "Start the Cloudflare quick tunnel" sudo "$REPO/host/install-quick-tunnel.sh"
    TUNNEL_URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$LOG" | tail -n 1 || true)
else
    info "Skipped. Run QUICK_TUNNEL=yes ./build.sh to publish noVNC at a public URL."
fi

# ---- summary ---------------------------------------------------------------

ELAPSED=$((SECONDS - START_TIME))
echo
printf '%s%s✓ Desktop is ready%s  %s(%dm%02ds)%s\n' "$BOLD" "$GREEN" "$RESET" \
    "$DIM" $((ELAPSED / 60)) $((ELAPSED % 60)) "$RESET"
echo
printf '  %sOpen%s      http://127.0.0.1:6080/vnc.html\n' "$BOLD" "$RESET"
printf '  %sLogin%s     user %sdesktop%s, password: sudo grep NOVNC_AUTH /etc/xfce4-container/auth.env\n' \
    "$BOLD" "$RESET" "$CYAN" "$RESET"
if [ -n "$TUNNEL_URL" ]; then
    printf '  %sPublic%s    %s/vnc.html  %s(login required)%s\n' "$BOLD" "$RESET" "$TUNNEL_URL" "$DIM" "$RESET"
fi
printf '  %sLog%s       %s\n' "$BOLD" "$RESET" "$LOG"
