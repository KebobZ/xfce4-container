#!/usr/bin/env bash
# macOS-style look: WhiteSur GTK, icon, and cursor themes, plus a generated wallpaper.
# Run inside the container as root. Each upstream is pinned to a fixed ref, and a rerun
# with the same refs does nothing.
set -euo pipefail

WHITESUR_GTK_REF=2026-09-10
WHITESUR_ICON_REF=2026-09-10
WHITESUR_CURSORS_REF=e190baf618ed95ee217d2fd45589bd309b37672b

WANT="$WHITESUR_GTK_REF $WHITESUR_ICON_REF $WHITESUR_CURSORS_REF"
MARK=/usr/share/xfce4-container/theme.ref

if [ -f "$MARK" ] && [ "$(cat "$MARK")" = "$WANT" ]; then
    echo "Theme refs already installed: $WANT"
    exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

git clone -q --depth 1 --branch "$WHITESUR_GTK_REF" \
    https://github.com/vinceliuice/WhiteSur-gtk-theme.git "$WORK/gtk"
tar -xJf "$WORK/gtk/release/WhiteSur-Light.tar.xz" -C /usr/share/themes
mkdir -p /usr/share/plank/themes
ln -sfn /usr/share/themes/WhiteSur-Light/plank /usr/share/plank/themes/WhiteSur-Light

git clone -q --depth 1 --branch "$WHITESUR_ICON_REF" \
    https://github.com/vinceliuice/WhiteSur-icon-theme.git "$WORK/icon"
"$WORK/icon/install.sh" -d /usr/share/icons -t default >/dev/null

git init -q "$WORK/cursors"
git -C "$WORK/cursors" fetch -q --depth 1 \
    https://github.com/vinceliuice/WhiteSur-cursors.git "$WHITESUR_CURSORS_REF"
git -C "$WORK/cursors" checkout -q FETCH_HEAD
rm -rf /usr/share/icons/WhiteSur-cursors
cp -r "$WORK/cursors/dist" /usr/share/icons/WhiteSur-cursors
mkdir -p /usr/share/icons/default
printf '[Icon Theme]\nInherits=WhiteSur-cursors\n' > /usr/share/icons/default/index.theme

# Generated wallpaper: a soft three-stop gradient, so no image is downloaded.
install -d /usr/share/backgrounds/xfce4-container
ffmpeg -loglevel error -y -f lavfi \
    -i "gradients=s=1920x1200:n=3:c0=0x4a78d8:c1=0x9a7fd1:c2=0xf0a8c4:x0=0:y0=0:x1=1920:y1=1200" \
    -frames:v 1 /usr/share/backgrounds/xfce4-container/wallpaper.png

install -d "$(dirname "$MARK")"
echo "$WANT" > "$MARK"
echo "Installed WhiteSur: $WANT"
