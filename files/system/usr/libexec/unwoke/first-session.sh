#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Graphical login helper: reboot nag + setup window.
# Does not change locks by itself.
set -euo pipefail

SEEN="${XDG_CONFIG_HOME:-$HOME/.config}/unwoke/setup-seen"
STAGED="/etc/unwoke/signed-staged"
SETUP="/usr/libexec/unwoke/setup.sh"
GUI="/usr/libexec/unwoke/setup-gui.py"

force=0
jump=()
for arg in "$@"; do
  case "${arg}" in
    --force|--gui) force=1 ;;
    --broken) jump+=(--broken) ;;
    --stock) jump+=(--stock) ;;
    --hardware) jump+=(--hardware) ;;
    --daily) jump+=(--daily) ;;
    --loosened) jump+=(--loosened) ;;
    --proton) jump+=(--proton) ;;
    --ivpn) jump+=(--ivpn) ;;
    --vendors) jump+=(--vendors) ;;
    --mullvad) jump+=(--mullvad) ;;
    --steam) jump+=(--steam) ;;
    --gaming|--play) jump+=(--gaming) ;;
    --whonix) jump+=(--whonix) ;;
  esac
done

notify() {
  command -v notify-send >/dev/null || return 0
  notify-send -u critical -a "Unwoke SecureBlue" "$1" "$2" || true
}

# Resume ostree-layer wizards after reboot (Whonix, vendor RPMs, IVPN, …).
CONT="${XDG_CONFIG_HOME:-$HOME/.config}/unwoke/continue"
if [[ ! -f "${CONT}" && -f "${XDG_CONFIG_HOME:-$HOME/.config}/unwoke/continue-whonix" ]]; then
  mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/unwoke"
  printf 'whonix\n' > "${CONT}"
fi
if [[ -f "${CONT}" ]]; then
  force=1
  kind="$(head -n1 "${CONT}" | tr -d '[:space:]')"
  extra="$(sed -n '2p' "${CONT}" | tr -d '[:space:]')"
  case "${kind}" in
    whonix) jump+=(--whonix) ;;
    ivpn) jump+=(--ivpn) ;;
    mullvad) jump+=(--mullvad) ;;
    proton) jump+=(--proton) ;;
    vendor) jump+=(--vendors) ;;
  esac
  notify "Finish install" "Layered packages are ready. The wizard continues. Locks stay on."
  export UNWOKE_CONTINUE_VENDOR="${extra}"
fi

if [[ -f "${STAGED}" ]]; then
  # Background: Reboot button must not block the setup window.
  bash /usr/libexec/unwoke/notify-reboot.sh --background || \
    notify "Reboot to lock updates" \
      "A signed Unwoke image is staged. Reboot once. Until then updates are not stamp-checked."
fi

[[ -x "${SETUP}" || -x "${GUI}" ]] || exit 0
if [[ "${force}" -eq 0 && -f "${SEEN}" ]]; then
  exit 0
fi

if [[ "${force}" -eq 0 ]]; then
  notify "Unwoke setup" \
    "A window will open. Locks stay on unless you turn one off. App grid: Unwoke setup."
fi

run_gui() {
  [[ -x "${GUI}" ]] || return 1
  command -v python3 >/dev/null || return 1
  python3 "${GUI}" "${jump[@]}"
}

run_tty() {
  if [[ ${#jump[@]} -gt 0 ]]; then
    exec bash "${SETUP}" "${jump[0]}"
  fi
  exec bash "${SETUP}"
}

if [[ -t 0 && -t 1 && "${force}" -eq 0 ]]; then
  if run_gui; then
    exit 0
  fi
  run_tty
fi

if run_gui; then
  exit 0
fi

cmd='bash /usr/libexec/unwoke/setup.sh; echo; read -r -p "Enter to close... " _ || true'
if [[ ${#jump[@]} -gt 0 ]]; then
  cmd="bash /usr/libexec/unwoke/setup.sh ${jump[0]}; echo; read -r -p \"Enter to close... \" _ || true"
fi

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
run_tty
