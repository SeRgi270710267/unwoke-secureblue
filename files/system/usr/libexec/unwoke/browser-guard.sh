#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Seatbelt, not a prison. Blocks the easy host-browser installs on browserless
# until /etc/unwoke/allow-browsers exists. Toolbox, brew, AppImage, and
# rpm-ostree --disableexcludes still work; those are intentional bypasses.
set -euo pipefail

FLATPAK_LIST="/usr/share/unwoke/block-browsers.flatpak"
RPM_LIST="/usr/share/unwoke/block-browsers.rpm"
STAMP="/etc/unwoke/allow-browsers"
DNF_DROP="/etc/dnf/dnf.conf.d/unwoke-block-browsers.conf"
FLAVOR="brave-origin"
if [[ -f /usr/share/unwoke/flavor ]]; then
  FLAVOR="$(tr -d '[:space:]' < /usr/share/unwoke/flavor)"
fi

ids() {
  [[ -f "$1" ]] || return 0
  sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$1"
}

is_browserless() { [[ "${FLAVOR}" == "browserless" ]]; }

allowed() { [[ -f "${STAMP}" ]]; }

mask_flatpak() {
  local inst="$1"
  command -v flatpak >/dev/null || return 0
  local id
  while IFS= read -r id; do
    [[ -n "${id}" ]] || continue
    flatpak mask "${inst}" "${id}" >/dev/null 2>&1 || true
  done < <(ids "${FLATPAK_LIST}")
}

unmask_flatpak() {
  local inst="$1"
  command -v flatpak >/dev/null || return 0
  local id
  while IFS= read -r id; do
    [[ -n "${id}" ]] || continue
    flatpak mask --remove "${inst}" "${id}" >/dev/null 2>&1 || true
  done < <(ids "${FLATPAK_LIST}")
}

write_dnf_exclude() {
  mkdir -p "$(dirname "${DNF_DROP}")"
  {
    echo "[main]"
    echo -n "excludepkgs="
    ids "${RPM_LIST}" | tr '\n' ',' | sed 's/,$//'
    echo
  } > "${DNF_DROP}"
}

cmd_apply() {
  local user_only=0
  [[ "${1:-}" == "--user" ]] && user_only=1
  if ! is_browserless; then
    exit 0
  fi
  if allowed; then
    exit 0
  fi
  if [[ "${user_only}" -eq 1 ]]; then
    mask_flatpak --user
    exit 0
  fi
  mask_flatpak --system
  write_dnf_exclude
}

cmd_lift() {
  mkdir -p /etc/unwoke
  touch "${STAMP}"
  unmask_flatpak --system
  rm -f "${DNF_DROP}"
  echo "unwoke: easy host browsers unmasked. Flathub is still off by default."
  echo "        Flatpak browsers: ujust set-flathub verified"
}

cmd_unmask_user() {
  unmask_flatpak --user
}

cmd_block() {
  rm -f "${STAMP}"
  cmd_apply
}

cmd_status() {
  if ! is_browserless; then
    echo "n/a (not a browserless image)"
    return 0
  fi
  if allowed; then
    echo "on (browsers allowed — ${STAMP})"
  else
    echo "off (easy host browsers blocked until: ujust set-allow-browsers on ALLOW)"
  fi
}

case "${1:-status}" in
  apply) shift || true; cmd_apply "${1:-}" ;;
  lift) cmd_lift ;;
  block) cmd_block ;;
  unmask-user) cmd_unmask_user ;;
  status) cmd_status ;;
  *)
    echo "usage: browser-guard.sh apply [--user]|lift|block|unmask-user|status" >&2
    exit 2
    ;;
esac
