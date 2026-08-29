#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated. UNWOKE-SHIPPED-FIRST. Stock #391 was a request.
# chmod 700 /boot. ostree /usr is image-owned; we do not chmod /usr.
# Revert: ujust set-boot-perm off
set -euo pipefail

ALLOW="/etc/unwoke/allow-boot-open"

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    command -v run0 >/dev/null || { echo "need run0 (wheel user)" >&2; exit 1; }
    run0 "$@"
  fi
}

wanted_lock() { [[ ! -f "${ALLOW}" ]]; }

cmd_apply_boot() {
  [[ "$(id -u)" -eq 0 ]] || exit 1
  [[ -d /boot ]] || return 0
  if wanted_lock; then
    chmod 700 /boot 2>/dev/null || true
  else
    chmod 755 /boot 2>/dev/null || true
  fi
}

cmd_on() {
  as_root mkdir -p /etc/unwoke
  as_root rm -f "${ALLOW}"
  as_root /usr/bin/bash /usr/libexec/unwoke/boot-perm.sh apply-boot
  echo "/boot mode 700. Revert: ujust set-boot-perm off"
}

cmd_off() {
  as_root mkdir -p /etc/unwoke
  as_root touch "${ALLOW}"
  as_root /usr/bin/bash /usr/libexec/unwoke/boot-perm.sh apply-boot
  echo "/boot mode 755. Put it back: ujust set-boot-perm on"
}

cmd_status() {
  if wanted_lock; then
    echo "on/locked (default — /boot 700)"
  else
    echo "off/open (${ALLOW})"
  fi
}

case "${1:-status}" in
  on|enable|lock) cmd_on ;;
  off|disable|open) cmd_off ;;
  apply-boot) cmd_apply_boot ;;
  status) cmd_status ;;
  *)
    echo "usage: ujust set-boot-perm on|off|status" >&2
    exit 2
    ;;
esac
