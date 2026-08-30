#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# First boot, after daily-user prompt: ask to generate USBGuard policy.
# Default is skip. Never silent-enable. Once asked, do not ask again.
set -euo pipefail

DONE="/etc/unwoke/usbguard-prompt.done"

[[ "$(id -u)" -eq 0 ]] || exit 0
mkdir -p /etc/unwoke
if [[ -f "${DONE}" ]]; then
  exit 0
fi

export TERM="${TERM:-linux}"
export NCURSES_NO_UTF8_ACS=1
ans=""

if command -v dialog >/dev/null && [[ -t 0 ]]; then
  dialog --backtitle "Unwoke SecureBlue" --title "USBGuard" --yesno \
    "Generate a USBGuard policy from devices plugged in NOW?\n\nDefault is No. This does not enroll a Secure Boot key.\nYes = allow current sticks/keyboards, block new IDs until you allow them.\nNo = skip. Later: Unwoke setup leftover stock, or ujust setup-usbguard." \
    16 64 && ans=y || ans=n
else
  echo
  echo "USBGuard: generate policy from devices plugged in now? [y/N]"
  echo "Default No. Later: ujust setup-usbguard"
  printf "> "
  read -r ans || true
fi

case "${ans}" in
  y|Y|yes|YES)
    if command -v ujust >/dev/null; then
      ujust setup-usbguard || echo "usbguard helper failed; later: ujust setup-usbguard"
    else
      echo "ujust missing; later: ujust setup-usbguard"
    fi
    ;;
  *)
    echo "Skipped USBGuard. Later: Unwoke setup → leftover stock, or ujust setup-usbguard"
    ;;
esac
touch "${DONE}"
exit 0
