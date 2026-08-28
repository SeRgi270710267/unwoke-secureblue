#!/usr/bin/env bash
# System Flathub remote: verified (stock), full, or off. Stamp: /etc/unwoke/flathub
set -euo pipefail

REPO="https://dl.flathub.org/repo/flathub.flatpakrepo"
STAMP="/etc/unwoke/flathub"
FLAVOR="brave-origin"
if [[ -f /usr/share/unwoke/flavor ]]; then
  FLAVOR="$(tr -d '[:space:]' < /usr/share/unwoke/flavor)"
fi

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    command -v run0 >/dev/null || { echo "need run0 (wheel user)" >&2; exit 1; }
    run0 "$@"
  fi
}

have_flatpak() { command -v flatpak >/dev/null; }

default_mode() {
  if [[ -f "${STAMP}" ]]; then
    tr -d '[:space:]' < "${STAMP}"
    return
  fi
  if [[ "${FLAVOR}" == "browserless" ]]; then
    echo off
  else
    echo verified
  fi
}

delete_system_flathub() {
  have_flatpak || return 0
  flatpak remote-delete --system --force flathub >/dev/null 2>&1 || true
  flatpak remote-delete --system --force flathub-verified >/dev/null 2>&1 || true
}

apply_mode() {
  local mode="$1"
  have_flatpak || { echo "flatpak not installed" >&2; return 0; }
  case "${mode}" in
    verified)
      delete_system_flathub
      flatpak remote-add --if-not-exists --system --subset=verified \
        --title="Flathub Verified" flathub "${REPO}"
      ;;
    full)
      delete_system_flathub
      flatpak remote-add --if-not-exists --system --title="Flathub" flathub "${REPO}"
      flatpak remote-modify --system --subset= flathub >/dev/null 2>&1 || true
      ;;
    off)
      delete_system_flathub
      ;;
    *)
      echo "usage: flathub.sh verified|full|off|status|apply" >&2
      exit 2
      ;;
  esac
}

write_stamp() {
  local mode="$1"
  mkdir -p /etc/unwoke
  printf '%s\n' "${mode}" > "${STAMP}"
}

cmd_set() {
  local mode="$1"
  case "${mode}" in
    verified|full|off) ;;
    *)
      echo "usage: ujust set-flathub verified|full|off|status" >&2
      exit 2
      ;;
  esac
  as_root /usr/bin/bash /usr/libexec/unwoke/flathub.sh apply-root "${mode}"
  echo "Flathub system remote: ${mode}"
  if [[ "${mode}" == "verified" ]]; then
    echo "Only Flathub-verified apps. ujust set-flathub full  to match today's Origin, or off."
  elif [[ "${mode}" == "full" ]]; then
    echo "Unfiltered Flathub. ujust set-flathub verified  to match stock."
  else
    echo "No system Flathub remote. ujust set-flathub verified  to add it back."
  fi
}

cmd_apply_root() {
  local mode="$1"
  write_stamp "${mode}"
  apply_mode "${mode}"
}

cmd_apply_boot() {
  local mode
  mode="$(default_mode)"
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "apply-boot must run as root" >&2
    exit 1
  fi
  write_stamp "${mode}"
  apply_mode "${mode}"
}

cmd_status() {
  local want
  want="$(default_mode)"
  echo "wanted: ${want} (${STAMP})"
  if ! have_flatpak; then
    echo "installed: n/a (no flatpak)"
    return 0
  fi
  if flatpak remotes --system --columns=name 2>/dev/null | grep -qx flathub; then
    local extra
    extra="$(flatpak remote-info --system flathub 2>/dev/null | tr '\n' ' ' || true)"
    if [[ "${extra}" == *subset=verified* ]] || [[ "${extra}" == *"Subset: verified"* ]]; then
      echo "installed: flathub (verified subset)"
    else
      echo "installed: flathub (full or unknown subset)"
    fi
  elif flatpak remotes --system --columns=name 2>/dev/null | grep -qx flathub-verified; then
    echo "installed: flathub-verified"
  else
    echo "installed: none"
  fi
}

case "${1:-status}" in
  verified|full|off) cmd_set "$1" ;;
  apply-root)
    [[ "$(id -u)" -eq 0 ]] || { echo "apply-root needs root" >&2; exit 1; }
    cmd_apply_root "${2:?mode}"
    ;;
  apply|apply-boot) cmd_apply_boot ;;
  status) cmd_status ;;
  *)
    echo "usage: flathub.sh verified|full|off|status|apply" >&2
    exit 2
    ;;
esac
