#!/usr/bin/env bash
# toolbox + distrobox off by default. /usr/bin/toolbox is our wrapper.
# Real binaries live in /usr/libexec/unwoke/real-bin/. podman stays.
set -euo pipefail

ALLOW="/etc/unwoke/allow-toolbox"

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    command -v run0 >/dev/null || { echo "need run0 (wheel user)" >&2; exit 1; }
    run0 "$@"
  fi
}

wanted_off() { [[ ! -f "${ALLOW}" ]]; }

cmd_on() {
  as_root mkdir -p /etc/unwoke
  as_root touch "${ALLOW}"
  echo "toolbox/distrobox ON (wrapper will exec the real binary). Revert: ujust set-toolbox off"
}

cmd_off() {
  as_root rm -f "${ALLOW}"
  echo "toolbox/distrobox OFF. /usr/bin/toolbox is a wrapper until ujust set-toolbox on"
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
  apply-boot) exit 0 ;;
  status) cmd_status ;;
  *)
    echo "usage: ujust set-toolbox on|off|status" >&2
    exit 2
    ;;
esac
