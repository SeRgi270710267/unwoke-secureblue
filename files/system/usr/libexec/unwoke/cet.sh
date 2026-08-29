#!/usr/bin/env bash
# Intel CET: SHSTK + IBT via glibc tunables (stock #1295). Default on. x86_64.
# Revert: ujust set-cet off
set -euo pipefail

ALLOW="/etc/unwoke/cet.off"
SYS_SRC="/usr/share/unwoke/cet-system.conf"
SYS_DST="/etc/systemd/system.conf.d/90-unwoke-cet.conf"
PROF_SRC="/usr/share/unwoke/cet-profile.sh"
PROF_DST="/etc/profile.d/zzz-unwoke-cet.sh"

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
  mkdir -p /etc/systemd/system.conf.d /etc/profile.d
  if wanted_on; then
    [[ -f "${SYS_SRC}" ]] && cp -a "${SYS_SRC}" "${SYS_DST}"
    [[ -f "${PROF_SRC}" ]] && cp -a "${PROF_SRC}" "${PROF_DST}"
  else
    rm -f "${SYS_DST}" "${PROF_DST}"
  fi
}

cmd_on() {
  as_root mkdir -p /etc/unwoke
  as_root rm -f "${ALLOW}"
  as_root /usr/bin/bash /usr/libexec/unwoke/cet.sh apply-boot
  echo "SHSTK/IBT ON (glibc tunables). New logins / systemd user sessions pick it up. Revert: ujust set-cet off"
}

cmd_off() {
  as_root mkdir -p /etc/unwoke
  as_root touch "${ALLOW}"
  as_root /usr/bin/bash /usr/libexec/unwoke/cet.sh apply-boot
  echo "SHSTK/IBT OFF. Put it back: ujust set-cet on"
}

cmd_status() {
  if wanted_on; then
    echo "on (default)"
  else
    echo "off (${ALLOW})"
  fi
}

case "${1:-status}" in
  on|enable) cmd_on ;;
  off|disable) cmd_off ;;
  apply-boot) cmd_apply_boot ;;
  status) cmd_status ;;
  *)
    echo "usage: ujust set-cet on|off|status" >&2
    exit 2
    ;;
esac
