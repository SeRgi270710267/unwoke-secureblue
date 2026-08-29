#!/usr/bin/env bash
# Repeat until the signed image is the booted origin.
set -euo pipefail
[[ -f /etc/unwoke/signed-staged ]] || exit 0
command -v notify-send >/dev/null || exit 0
notify-send -u critical -a "Unwoke SecureBlue" \
  "Reboot to lock updates" \
  "A signed Unwoke image is still staged. Reboot once. App grid: Unwoke setup." || true
