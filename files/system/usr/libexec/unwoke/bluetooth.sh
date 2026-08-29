#!/usr/bin/env bash
# Bluetooth off by default. Wi-Fi is not touched. ujust set-bluetooth on|off|status
set -euo pipefail

ALLOW="/etc/unwoke/allow-bluetooth"
UNITS=(bluetooth.service obex.service)

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
    command -v rfkill >/dev/null && rfkill block bluetooth >/dev/null 2>&1 || true
  else
    for u in "${UNITS[@]}"; do
      systemctl unmask "$u" >/dev/null 2>&1 || true
    done
    systemctl enable --now bluetooth.service >/dev/null 2>&1 || true
    command -v rfkill >/dev/null && rfkill unblock bluetooth >/dev/null 2>&1 || true
  fi
}

cmd_on() {
  as_root mkdir -p /etc/unwoke
  as_root touch "${ALLOW}"
  as_root /usr/bin/bash /usr/libexec/unwoke/bluetooth.sh apply-boot
  echo "Bluetooth ON. Revert: ujust set-bluetooth off"
}

cmd_off() {
  as_root rm -f "${ALLOW}"
  as_root /usr/bin/bash /usr/libexec/unwoke/bluetooth.sh apply-boot
  echo "Bluetooth OFF (service masked, rfkill block). Wi-Fi unchanged. Revert: ujust set-bluetooth on"
}

cmd_status() {
  if wanted_off; then
    echo "off (default — ${ALLOW} absent)"
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
    echo "usage: ujust set-bluetooth on|off|status" >&2
    exit 2
    ;;
esac
