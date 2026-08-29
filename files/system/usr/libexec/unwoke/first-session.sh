#!/usr/bin/env bash
# Graphical login helper: reboot nag + optional setup window.
# Does not change locks by itself.
set -euo pipefail

SEEN="${XDG_CONFIG_HOME:-$HOME/.config}/unwoke/setup-seen"
STAGED="/etc/unwoke/signed-staged"
SETUP="/usr/libexec/unwoke/setup.sh"

notify() {
  command -v notify-send >/dev/null || return 0
  notify-send -u critical -a "Unwoke SecureBlue" "$1" "$2" || true
}

if [[ -f "${STAGED}" ]]; then
  notify "Reboot to lock updates" \
    "A signed Unwoke image is staged. Reboot once. Until then updates are not stamp-checked."
fi

[[ -x "${SETUP}" ]] || exit 0
[[ ! -f "${SEEN}" ]] || exit 0

# Already in a terminal (ujust first-session).
if [[ -t 0 && -t 1 ]]; then
  exec bash "${SETUP}"
fi

cmd='bash /usr/libexec/unwoke/setup.sh; echo; read -r -p "Enter to close... " _ || true'

if command -v ptyxis >/dev/null; then
  exec ptyxis -- bash -lc "${cmd}"
fi
if command -v kgx >/dev/null; then
  exec kgx -e bash -lc "${cmd}"
fi
if command -v gnome-terminal >/dev/null; then
  exec gnome-terminal -- bash -lc "${cmd}"
fi
if command -v konsole >/dev/null; then
  exec konsole -e bash -lc "${cmd}"
fi
exec bash "${SETUP}"
