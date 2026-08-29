#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Signed-image nag with a Reboot button when libnotify supports --action.
set -euo pipefail
[[ -f /etc/unwoke/signed-staged ]] || exit 0
command -v notify-send >/dev/null || exit 0

TITLE="Reboot to lock updates"
BODY="A signed Unwoke image is staged. Reboot once. Until then updates are not stamp-checked."

background=0
[[ "${1:-}" == "--background" ]] && background=1

do_reboot() {
  if command -v systemctl >/dev/null; then
    systemctl reboot && return 0
  fi
  if command -v loginctl >/dev/null; then
    loginctl reboot && return 0
  fi
  reboot || true
}

notify_with_action() {
  local act=""
  act="$(notify-send -u critical -a "Unwoke SecureBlue" \
    --wait --expire-time=120000 \
    --action=reboot=Reboot \
    --action=later=Later \
    "${TITLE}" \
    "${BODY} This nag repeats until you reboot." 2>/dev/null || true)"
  if [[ "${act}" == "reboot" ]]; then
    do_reboot
  fi
}

notify_plain() {
  notify-send -u critical -a "Unwoke SecureBlue" "${TITLE}" \
    "${BODY} App grid: Unwoke setup." || true
}

run() {
  if notify-send --help 2>&1 | grep -q -- '--action'; then
    notify_with_action
  else
    notify_plain
  fi
}

if [[ "${background}" -eq 1 ]]; then
  run &
  disown || true
  exit 0
fi
run
