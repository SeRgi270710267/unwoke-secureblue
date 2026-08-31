#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Desktop Steam icon. GameMode wraps the process. The login agent restores
# locks when Steam exits. Do not ask the user to type play stop.
set -euo pipefail
systemctl --user start gamemoded.service >/dev/null 2>&1 || true
systemctl --user start unwoke-play-agent.service >/dev/null 2>&1 || true
/usr/libexec/unwoke/play-window.sh arm >/dev/null 2>&1 || true
# Proton on Fedora 44: NTsync/fsync. Not a security cut. Restores by process exit.
export PROTON_USE_NTSYNC="${PROTON_USE_NTSYNC:-1}"
export WINEFSYNC="${WINEFSYNC:-1}"
export WINEESYNC="${WINEESYNC:-1}"
if command -v flatpak >/dev/null && flatpak info com.valvesoftware.Steam >/dev/null 2>&1; then
  if command -v gamemoderun >/dev/null; then
    exec gamemoderun flatpak run com.valvesoftware.Steam "$@"
  fi
  exec flatpak run com.valvesoftware.Steam "$@"
fi
if command -v steam >/dev/null; then
  if command -v gamemoderun >/dev/null; then
    exec gamemoderun steam "$@"
  fi
  exec steam "$@"
fi
echo "Steam is not installed. ujust install-steam" >&2
exit 1
