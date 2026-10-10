# xfce4-container

An Ubuntu 26.04 Incus container running an XFCE desktop with a macOS-style look, reached
from a browser through noVNC on the host's loopback interface.

## What you get

- **Container:** `images:ubuntu/26.04`, nested containers enabled (Docker runs inside).
- **Desktop:** XFCE on a TigerVNC display (`:1`), WhiteSur GTK/icons/cursors, Inter and
  JetBrains Mono fonts, a translucent top bar, a Plank dock with Chrome and the terminal,
  and a Catppuccin terminal palette.
- **Browser:** Google Chrome with its sandbox on. The host allows the unprivileged user
  namespaces the sandbox needs (`host/allow-userns.sh`).
- **Access:** noVNC at `http://127.0.0.1:6080/vnc.html` on the host, behind a Basic-auth
  login. The optional quick tunnel publishes that page at a random public URL.

## Requirements

- Ubuntu 26.04 host with `sudo` access and a working `apt`.
- Enough disk for the container image, XFCE, Chrome, and Docker images. The exact size
  depends on what you run.

## Build

```bash
./build.sh
```

The script is safe to re-run. Each stage checks its own state and skips finished work.
To give the desktop user passwordless sudo inside the container. Run again without the
variable to take it away:

```bash
DESKTOP_SUDO=yes ./build.sh
```

To publish the login page through a Cloudflare quick tunnel:

```bash
QUICK_TUNNEL=yes ./build.sh
```

## Stages

Each stage prints a numbered banner, and every step shows a spinner and its duration.
Full output goes to `build.log`.

| # | Stage | What it does |
|---|-------|--------------|
| 1 | Host checks | Caches sudo, preflight, and the root subordinate ID range Incus needs |
| 2 | Host packages and container | Installs Incus, noVNC, and websockify; launches `xfce` |
| 3 | Container packages and desktop user | Copies the project in; installs XFCE, TigerVNC, Docker, fonts |
| 4 | WhiteSur theme and wallpaper | Installs WhiteSur from pinned refs; generates the wallpaper |
| 5 | Google Chrome | Allows user namespaces on the host, installs Chrome's `.deb`, checks the sandbox |
| 6 | Desktop session | Installs config and user services; waits for XFCE on `:1`; sets passwordless sudo per `DESKTOP_SUDO` |
| 7 | Login and noVNC gateway | Creates the login, the loopback VNC proxy, and the gateway service |
| 8 | Resource limits | Container process limit and optional disk size |
| 9 | Docker checks | Build, Compose, and published-port test |
| 10 | Public access (opt-in) | Cloudflare quick tunnel, only with `QUICK_TUNNEL=yes` |

## Layout

```
build.sh                 orchestrates the stages and shows progress
host/                    runs on the Ubuntu host (sudo)
  bootstrap-incus.sh     Incus, the container, UFW rules for the bridge
  allow-userns.sh        host sysctl that lets Chrome's sandbox start
  install-novnc.sh       noVNC login, VNC proxy device, gateway service
  install-quick-tunnel.sh
  resource-policy.sh
  systemd/               gateway and tunnel units
container/               runs inside the container (as root)
  bootstrap.sh           packages and the desktop user
  desktop-sudo.sh        passwordless sudo for the desktop user (DESKTOP_SUDO)
  theme.sh               WhiteSur and wallpaper
  chrome-install.sh      Chrome .deb
  desktop-setup.sh       config files, user units, session start
  docker-check.sh
  systemd/               user units for VNC and the XFCE session
  config/                files copied to their target paths (etc/, usr/, home/)
```

## Access and credentials

Open `http://127.0.0.1:6080/vnc.html`. The browser asks for the Basic-auth login:

- user: `desktop`
- password: `sudo grep NOVNC_AUTH /etc/xfce4-container/auth.env`

The VNC server inside the container has no password of its own. It listens only on the
container's loopback interface. Only the host's loopback proxy can reach it. The login
above is the only gate, so keep the quick tunnel off unless you need public access.

## Notes

- **No GPU passthrough.** The desktop renders in software (Mesa llvmpipe). This is
  enough for XFCE and Chrome, and needs no DRM devices.
- **Desktop sudo is a loosening.** With `DESKTOP_SUDO=yes`, anything running as `desktop`,
  Chrome included, can become root in the container. The container is still unprivileged.
- **Chrome's sandbox needs a host setting.** `host/allow-userns.sh` sets
  `kernel.apparmor_restrict_unprivileged_userns=0` on the host. That's a host-wide weakening
  of an Ubuntu hardening default. Stage 5 checks that the sandbox starts.
- **Chrome tracks Google's current stable build,** so rebuilding or upgrading the
  container pulls a newer Chrome.
- **Container cleanup:** `sudo incus delete xfce --force` removes the container. Then
  `sudo systemctl disable --now xfce-novnc` stops the gateway. Delete the unit file from
  `/etc/systemd/system/` too.
