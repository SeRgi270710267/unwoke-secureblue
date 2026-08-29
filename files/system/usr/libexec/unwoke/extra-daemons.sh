#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Extra daemons stock still leaves on: Avahi (.local/mDNS) and ModemManager.
# cups/geoclue/passim are already masked by secureblue. Bluetooth is set-bluetooth.
# Default off. ujust set-extra-daemons on|off|status
set -euo pipefail

ALLOW="/etc/unwoke/allow-extra-daemons"
UNITS=(
  avahi-daemon.service
  avahi-daemon.socket
  ModemManager.service
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

cmd_apply_boot() {
  [[ "$(id -u)" -eq 0 ]] || exit 1
  local u
  if wanted_off; then
    for u in "${UNITS[@]}"; do
      systemctl disable --now "$u" >/dev/null 2>&1 || true
      systemctl mask "$u" >/dev/null 2>&1 || true
    done
  else
    for u in "${UNITS[@]}"; do
      systemctl unmask "$u" >/dev/null 2>&1 || true
    done
    systemctl enable --now avahi-daemon.service >/dev/null 2>&1 || true
    systemctl enable --now ModemManager.service >/dev/null 2>&1 || true
  fi
}

cmd_on() {
  as_root mkdir -p /etc/unwoke
  as_root touch "${ALLOW}"
  as_root /usr/bin/bash /usr/libexec/unwoke/extra-daemons.sh apply-boot
  echo "Avahi + ModemManager ON. Revert: ujust set-extra-daemons off"
}

cmd_off() {
  as_root rm -f "${ALLOW}"
  as_root /usr/bin/bash /usr/libexec/unwoke/extra-daemons.sh apply-boot
  echo "Avahi + ModemManager OFF (masked). Printers/geoclue are stock's problem. Revert: ujust set-extra-daemons on"
}

cmd_status() {
  if wanted_off; then
    echo "off (default — Avahi/ModemManager masked)"
  else
    echo "on (${ALLOW})"
  fi
}

case "${1:-status}" in
  on|enable) cmd_on ;;
  off|disable) cmd_off ;;
  apply-boot) cmd_apply_boot ;;
  status) cmd_status ;;
  *)
    echo "usage: ujust set-extra-daemons on|off|status" >&2
    exit 2
    ;;
esac
