#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated. UNWOKE-SHIPPED-FIRST. Stock #1185 was a request.
# Chrony NTS on the installed OS (and the live ISO). Independent of dns-selector.
# Revert: ujust set-nts off
set -euo pipefail

ALLOW="/etc/unwoke/allow-clear-ntp"
SRC="/usr/share/unwoke/chrony-nts.conf"
DST="/etc/chrony.d/50-unwoke-nts.conf"

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    command -v run0 >/dev/null || { echo "need run0 (wheel user)" >&2; exit 1; }
    run0 "$@"
  fi
}

wanted_on() { [[ ! -f "${ALLOW}" ]]; }

cmd_apply_boot() {
  [[ "$(id -u)" -eq 0 ]] || exit 1
  mkdir -p /etc/chrony.d /etc/unwoke
  if wanted_on; then
    [[ -f "${SRC}" ]] || return 0
    cp -a "${SRC}" "${DST}"
    systemctl try-reload-or-restart chronyd.service >/dev/null 2>&1 || true
  else
    rm -f "${DST}"
    systemctl try-reload-or-restart chronyd.service >/dev/null 2>&1 || true
  fi
}

cmd_on() {
  as_root mkdir -p /etc/unwoke
  as_root rm -f "${ALLOW}"
  as_root /usr/bin/bash /usr/libexec/unwoke/nts.sh apply-boot
  echo "Chrony NTS ON (Cloudflare + nts.ntp.se). Revert: ujust set-nts off"
}

cmd_off() {
  as_root mkdir -p /etc/unwoke
  as_root touch "${ALLOW}"
  as_root /usr/bin/bash /usr/libexec/unwoke/nts.sh apply-boot
  echo "Chrony NTS drop-in removed. Put it back: ujust set-nts on"
}

cmd_status() {
  if wanted_on; then
    echo "on (default — NTS ${DST})"
  else
    echo "off (${ALLOW})"
  fi
}

case "${1:-status}" in
  on|enable|lock) cmd_on ;;
  off|disable) cmd_off ;;
  apply-boot) cmd_apply_boot ;;
  status) cmd_status ;;
  *)
    echo "usage: ujust set-nts on|off|status" >&2
    exit 2
    ;;
esac
