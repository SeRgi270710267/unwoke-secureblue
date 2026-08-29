#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Stock user timers that can fight Unwoke (Flathub-off) or tell people to
# rebase back to ghcr.io/secureblue. Default masked. Secure Boot key
# enrollment check stays (you still need their ISO key).
# ujust set-stock-nags on|off|status
set -euo pipefail

ALLOW="/etc/unwoke/allow-stock-nags"
UNITS=(
  image-deprecation-notice.service
  secureblue-update-verification.service
  secureblue-update-verification.timer
  secureblue-flatpak-setup.service
  secureblue-flatpak-setup.timer
)

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    command -v run0 >/dev/null || { echo "need run0 (wheel user)" >&2; exit 1; }
    run0 "$@"
  fi
}

wanted_off() { [[ ! -f "${ALLOW}" ]]; }

cmd_apply_user() {
  command -v systemctl >/dev/null || return 0
  local u
  if wanted_off; then
    for u in "${UNITS[@]}"; do
      systemctl --user disable --now "$u" >/dev/null 2>&1 || true
      systemctl --user mask "$u" >/dev/null 2>&1 || true
    done
  else
    for u in "${UNITS[@]}"; do
      systemctl --user unmask "$u" >/dev/null 2>&1 || true
    done
  fi
}

cmd_on() {
  as_root mkdir -p /etc/unwoke
  as_root touch "${ALLOW}"
  cmd_apply_user
  echo "Stock nags ON (deprecation / update-verify / their flatpak-setup). Revert: ujust set-stock-nags off"
}

cmd_off() {
  as_root rm -f "${ALLOW}"
  cmd_apply_user
  echo "Stock nags OFF (default). Their Secure Boot key check still runs. Revert: ujust set-stock-nags on"
}

cmd_status() {
  if wanted_off; then
    echo "off (default — deprecation/update-verify/flatpak-setup masked)"
  else
    echo "on (${ALLOW})"
  fi
}

case "${1:-status}" in
  on|enable) cmd_on ;;
  off|disable) cmd_off ;;
  apply-user) cmd_apply_user ;;
  status) cmd_status ;;
  *)
    echo "usage: ujust set-stock-nags on|off|status" >&2
    exit 2
    ;;
esac
