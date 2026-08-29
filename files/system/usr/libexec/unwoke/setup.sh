#!/usr/bin/env bash
# First-session / ujust setup. Defaults stay locked unless the user turns one off.
set -euo pipefail

TOGGLES="/usr/libexec/unwoke/toggles.sh"
SEEN="${XDG_CONFIG_HOME:-$HOME/.config}/unwoke/setup-seen"
STAGED="/etc/unwoke/signed-staged"

need_toggles() {
  [[ -x "${TOGGLES}" ]] || { echo "missing ${TOGGLES}" >&2; exit 1; }
}

mark_seen() {
  mkdir -p "$(dirname "${SEEN}")"
  date -u +%Y-%m-%dT%H:%M:%SZ > "${SEEN}"
}

reboot_now() {
  if command -v systemctl >/dev/null; then
    systemctl reboot
  else
    reboot
  fi
}

header() {
  echo
  echo "Unwoke SecureBlue setup"
  echo "Locks stay on unless you turn one off."
  if [[ -f /usr/share/unwoke/flavor ]]; then
    echo "Flavor: $(tr -d '[:space:]' < /usr/share/unwoke/flavor)"
  fi
  if [[ -f "${STAGED}" ]]; then
    echo
    echo "A signed update is staged. Reboot once to lock updates to our key."
  fi
  echo
}

menu() {
  cat <<'EOF'
  1) Keep all defaults (recommended)
  2) Flathub: verified apps
  3) Bluetooth on (Wi-Fi is already on)
  4) Camera / microphone on
  5) Toolbox / distrobox on
  6) Homebrew on
  7) Sites broken? Allow JavaScript JIT
  8) Origin GPU broken? Turn Bubblejail off
  s) Show status
  r) Reboot now
  n) Do not show this on login again
  q) Quit
EOF
}

run_toggle() {
  need_toggles
  "${TOGGLES}" "$@"
}

loop() {
  header
  while true; do
    menu
    echo
    read -r -p "Choice: " ans || exit 0
    case "${ans}" in
      1)
        mark_seen
        echo "Defaults kept. Later: ujust setup"
        return 0
        ;;
      2)
        run_toggle flathub verified
        ;;
      3)
        run_toggle bluetooth on
        ;;
      4)
        run_toggle camera-mic on
        ;;
      5)
        run_toggle toolbox on
        ;;
      6)
        run_toggle brew on
        ;;
      7)
        run_toggle jitless off
        echo "Restart the house browser."
        ;;
      8)
        run_toggle bubblejail off
        echo "Origin only. Restart Brave Origin."
        ;;
      s|S)
        run_toggle status
        ;;
      r|R)
        echo "Rebooting."
        reboot_now
        ;;
      n|N)
        mark_seen
        echo "Won't open on login. Run: ujust setup"
        return 0
        ;;
      q|Q|"")
        return 0
        ;;
      *)
        echo "Unknown choice."
        ;;
    esac
    echo
  done
}

loop
