#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# USBGuard: asked, default No. Never silent-enable.
# Boot: --defer (do not block GDM on tty1). GUI: Unwoke setup.
set -euo pipefail

DONE="/etc/unwoke/usbguard-prompt.done"
PENDING="/etc/unwoke/usbguard-prompt.pending"

as_root_touch() {
  if [[ "$(id -u)" -eq 0 ]]; then
    mkdir -p /etc/unwoke
    "$@"
  else
    command -v run0 >/dev/null || { echo "need run0 (wheel)" >&2; return 1; }
    run0 mkdir -p /etc/unwoke
    run0 "$@"
  fi
}

mark_done() {
  if [[ "$(id -u)" -eq 0 ]]; then
    mkdir -p /etc/unwoke
    touch "${DONE}"
    rm -f "${PENDING}"
  else
    command -v run0 >/dev/null || return 0
    run0 mkdir -p /etc/unwoke
    run0 touch "${DONE}"
    run0 rm -f "${PENDING}"
  fi
}

run_yes() {
  if command -v ujust >/dev/null; then
    ujust setup-usbguard || echo "usbguard helper failed; later: ujust setup-usbguard"
  else
    echo "ujust missing; later: ujust setup-usbguard"
  fi
  mark_done
}

run_no() {
  echo "Skipped USBGuard. Default. Later: Unwoke setup → leftover stock, or ujust setup-usbguard"
  mark_done
}

gui_ask() {
  [[ -f "${DONE}" ]] && { echo "USBGuard already asked."; exit 0; }
  python3 - <<'PY'
import sys
try:
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gtk
except Exception:
    sys.exit(2)
d = Gtk.MessageDialog(
    flags=0,
    message_type=Gtk.MessageType.QUESTION,
    buttons=Gtk.ButtonsType.NONE,
    text="USBGuard from devices plugged in now?",
)
d.format_secondary_text(
    "Default is No. This does not enroll Secure Boot.\n"
    "Yes = allow current keyboards/sticks, block new IDs until you allow them.\n"
    "No = leave USBGuard unconfigured (stock leftover). You can run this later."
)
d.add_button("No (default)", Gtk.ResponseType.NO)
d.add_button("Yes", Gtk.ResponseType.YES)
d.set_default_response(Gtk.ResponseType.NO)
r = d.run()
d.destroy()
sys.exit(0 if r == Gtk.ResponseType.YES else 1)
PY
  rc=$?
  if [[ "${rc}" -eq 0 ]]; then
    run_yes
  else
    run_no
  fi
}

case "${1:-defer}" in
  --defer|defer)
    [[ "$(id -u)" -eq 0 ]] || exit 0
    [[ -f "${DONE}" ]] && exit 0
    mkdir -p /etc/unwoke
    touch "${PENDING}"
    exit 0
    ;;
  --gui|gui)
    gui_ask
    exit 0
    ;;
  --tty|tty)
    # Fallback if someone runs it on a console. Still default No. Do not block GDM.
    [[ "$(id -u)" -eq 0 ]] || exit 0
    [[ -f "${DONE}" ]] && exit 0
    mkdir -p /etc/unwoke
    echo "USBGuard: generate policy from devices plugged in now? [y/N]"
    printf "> "
    read -r ans || true
    case "${ans}" in
      y|Y|yes|YES) run_yes ;;
      *) run_no ;;
    esac
    exit 0
    ;;
  *)
    echo "usage: usbguard-prompt.sh --defer|--gui|--tty" >&2
    exit 2
    ;;
esac
