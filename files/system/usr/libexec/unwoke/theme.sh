#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Default Unwoke wallpaper, lock screen, dark + blue accent.
# GNOME: gschema defaults + GTK CSS. KDE: wallpaper package + AccentColor.
set -euo pipefail

DESKTOP="/usr/share/backgrounds/unwoke/unwoke-desktop.jpg"
LOCK="/usr/share/backgrounds/unwoke/unwoke-lock.jpg"
KDE_IMG="/usr/share/wallpapers/UnwokeSecureBlue/contents/images/1280x720.jpg"
STAMP_USER="${XDG_CONFIG_HOME:-$HOME/.config}/unwoke/theme.applied"

ok() { printf '  [ok]  %s\n' "$*"; }
info() { printf '  [--]  %s\n' "$*"; }

ensure_ini_key() {
  local file="$1" section="$2" key="$3" value="$4"
  mkdir -p "$(dirname "$file")"
  if [[ ! -f "$file" ]]; then
    printf '[%s]\n%s=%s\n' "$section" "$key" "$value" > "$file"
    return
  fi
  if grep -q "^${key}=" "$file"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    return
  fi
  if grep -q "^\[${section}\]" "$file"; then
    sed -i "/^\[${section}\]/a ${key}=${value}" "$file"
  else
    printf '\n[%s]\n%s=%s\n' "$section" "$key" "$value" >> "$file"
  fi
}

patch_plasma_defaults() {
  local f theme
  for f in \
    /usr/share/plasma/look-and-feel/org.kde.breezedark.desktop/contents/defaults \
    /usr/share/plasma/look-and-feel/org.kde.breeze.desktop/contents/defaults \
    /usr/share/plasma/look-and-feel/org.kde.breezedark/contents/defaults \
    /usr/share/plasma/look-and-feel/org.kde.breeze/contents/defaults
  do
    [[ -f "$f" ]] || continue
    if grep -q '^defaultWallpaperTheme=' "$f"; then
      sed -i 's|^defaultWallpaperTheme=.*|defaultWallpaperTheme=UnwokeSecureBlue|' "$f"
    else
      printf '\n[Wallpaper]\ndefaultWallpaperTheme=UnwokeSecureBlue\ndefaultFileSuffix=.jpg\n' >> "$f"
    fi
    grep -q '^defaultFileSuffix=' "$f" || sed -i '/^defaultWallpaperTheme=/a defaultFileSuffix=.jpg' "$f"
  done
  for theme in \
    /usr/share/kde-settings/kde-profile/default/share/config/kdeglobals \
    /usr/etc/xdg/kdeglobals \
    /etc/xdg/kdeglobals
  do
    [[ -f "$theme" || "$theme" == /usr/etc/xdg/kdeglobals ]] || continue
    ensure_ini_key "$theme" "General" "AccentColor" "59,108,255"
    ensure_ini_key "$theme" "General" "LastUsedCustomAccentColor" "59,108,255"
  done
}

cmd_apply_build() {
  patch_plasma_defaults
  if command -v dconf >/dev/null; then
    mkdir -p /etc/dconf/db/gdm.d /usr/etc/dconf/db/gdm.d
    dconf update || true
  fi
  if command -v glib-compile-schemas >/dev/null && [[ -d /usr/share/glib-2.0/schemas ]]; then
    glib-compile-schemas /usr/share/glib-2.0/schemas || true
  fi
  echo "unwoke: theme defaults installed (${DESKTOP})"
}

cmd_apply_user() {
  mkdir -p "$(dirname "${STAMP_USER}")"
  if command -v plasma-apply-wallpaperimage >/dev/null && [[ -f "${KDE_IMG}" ]]; then
    plasma-apply-wallpaperimage "${KDE_IMG}" >/dev/null 2>&1 || true
  fi
  if command -v plasma-apply-colorscheme >/dev/null; then
    plasma-apply-colorscheme BreezeDark >/dev/null 2>&1 || true
  fi
  if command -v kwriteconfig6 >/dev/null; then
    kwriteconfig6 --file kdeglobals --group General --key AccentColor "59,108,255" || true
    kwriteconfig6 --file kdeglobals --group General --key LastUsedCustomAccentColor "59,108,255" || true
  elif command -v kwriteconfig5 >/dev/null; then
    kwriteconfig5 --file kdeglobals --group General --key AccentColor "59,108,255" || true
  fi
  touch "${STAMP_USER}"
}

cmd_apply_user_once() {
  [[ -f "${STAMP_USER}" ]] && return 0
  cmd_apply_user
}

cmd_status() {
  if [[ -f "${DESKTOP}" ]]; then
    ok "desktop wallpaper ${DESKTOP}"
  else
    info "desktop wallpaper missing"
  fi
  if [[ -f "${LOCK}" ]]; then
    ok "lock wallpaper ${LOCK}"
  else
    info "lock wallpaper missing"
  fi
  info "GNOME accent: named blue + GTK #3b6cff (Shell cannot take a custom hex)"
  info "KDE accent: 59,108,255. Change wallpaper in Settings anytime."
}

case "${1:-status}" in
  apply-build) cmd_apply_build ;;
  apply-user) cmd_apply_user ;;
  apply-user-once) cmd_apply_user_once ;;
  apply) cmd_apply_user ;;
  status) cmd_status ;;
  *)
    echo "usage: theme.sh apply|status" >&2
    exit 2
    ;;
esac
