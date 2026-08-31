#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Stock ujust set-flathub-unfiltered fights our /etc/unwoke/flathub stamp
# (next boot apply-boot would drop the remote). Map onto our toggle.
set -euo pipefail
arg="${1:-status}"
case "${arg}" in
  on|enable|true|full)
    echo "Stock set-flathub-unfiltered → Unwoke ujust set-flathub full (stamp so it survives reboot)."
    exec /usr/libexec/unwoke/toggles.sh flathub full
    ;;
  off|disable|false)
    echo "Stock set-flathub-unfiltered off → Unwoke Flathub off (default)."
    exec /usr/libexec/unwoke/toggles.sh flathub off
    ;;
  status)
    exec /usr/libexec/unwoke/toggles.sh flathub status
    ;;
  *)
    echo "usage: ujust set-flathub-unfiltered on|off|status" >&2
    echo "Prefer: ujust set-flathub verified|full|off" >&2
    exit 2
    ;;
esac
