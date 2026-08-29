#!/usr/bin/env bash
# Distrust Fedora CAs that are not Mozilla website-trusted (stock #1606).
# Default on. Some TLS (gov/old Symantec) will fail. Revert: ujust set-extra-cas on
set -euo pipefail

ALLOW="/etc/unwoke/allow-extra-cas"
DST="/etc/pki/ca-trust/source/blocklist"
SRC="/usr/share/unwoke/ca-blocklist"

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
  mkdir -p "${DST}"
  rm -f "${DST}"/unwoke-*.pem
  if wanted_on && [[ -d "${SRC}" ]]; then
    local f
    for f in "${SRC}"/*.pem; do
      [[ -f "${f}" ]] || continue
      cp -a "${f}" "${DST}/unwoke-$(basename "${f}")"
    done
  fi
  if command -v update-ca-trust >/dev/null; then
    update-ca-trust extract >/dev/null 2>&1 || true
  fi
}

cmd_on() {
  as_root mkdir -p /etc/unwoke
  as_root rm -f "${ALLOW}"
  as_root /usr/bin/bash /usr/libexec/unwoke/ca-trim.sh apply-boot
  echo "Extra CAs BLOCKED (Mozilla website set). Some TLS will fail. Revert: ujust set-extra-cas on"
}

cmd_off() {
  as_root mkdir -p /etc/unwoke
  as_root touch "${ALLOW}"
  as_root /usr/bin/bash /usr/libexec/unwoke/ca-trim.sh apply-boot
  echo "Fedora extra CAs ALLOWED. Put the trim back: ujust set-extra-cas off"
}

cmd_status() {
  if wanted_on; then
    echo "off/trimmed (default — Mozilla website CAs)"
  else
    echo "on/extra allowed (${ALLOW})"
  fi
}

case "${1:-status}" in
  on|enable|allow) cmd_off ;;
  off|disable|trim|block) cmd_on ;;
  apply-boot) cmd_apply_boot ;;
  status) cmd_status ;;
  *)
    echo "usage: ujust set-extra-cas on|off|status" >&2
    exit 2
    ;;
esac
