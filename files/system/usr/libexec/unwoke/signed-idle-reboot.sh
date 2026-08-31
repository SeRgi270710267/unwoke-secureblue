#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Once: if a signed image is staged and no real user is logged in, reboot onto it.
# Never reboot a logged-in session. Never loop (done stamp).
set -euo pipefail

STAGED="/etc/unwoke/signed-staged"
DONE="/etc/unwoke/signed-idle-reboot.done"

[[ "$(id -u)" -eq 0 ]] || exit 0
[[ -f "${STAGED}" ]] || exit 0
[[ ! -f "${DONE}" ]] || exit 0

if pgrep -f 'rpm-ostree rebase' >/dev/null 2>&1; then
  exit 0
fi

# Any session whose user is not the display manager.
if command -v loginctl >/dev/null; then
  while read -r _sess uid user _; do
    [[ -n "${user}" ]] || continue
    case "${user}" in
      gdm|sddm|lightdm|greeter|gnome-initial-setup) continue ;;
    esac
    # A person is logged in — nag instead, do not reboot.
    exit 0
  done < <(loginctl list-sessions --no-legend 2>/dev/null || true)
fi

mkdir -p /etc/unwoke
touch "${DONE}"
systemctl reboot
