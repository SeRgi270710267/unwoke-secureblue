#!/usr/bin/env bash
# toolbox + distrobox off by default. podman stays (Flatpak does not need it).
# Interactive PATH is shadowed. /usr/bin/toolbox is a seatbelt, not a prison.
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
  echo "toolbox/distrobox ON. Open a new shell. Revert: ujust set-toolbox off"
}

cmd_off() {
  as_root rm -f "${ALLOW}"
  echo "toolbox/distrobox OFF. New shells hit the stub. Revert: ujust set-toolbox on"
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
