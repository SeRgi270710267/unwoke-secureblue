#!/usr/bin/env bash
# Block Flatpak Pulse/PipeWire *record* (mic + what other apps play).
# Default on. Independent of set-flatpak-lockdown so loosening FS does not
# re-open the microphone to Flatpaks. Revert: ujust set-flatpak-record off
set -euo pipefail

STAMP_OFF="/etc/unwoke/flatpak-record.off"

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    command -v run0 >/dev/null || { echo "need run0 (wheel user)" >&2; exit 1; }
    run0 "$@"
  fi
}

wanted_on() { [[ ! -f "${STAMP_OFF}" ]]; }

apply_one() {
  local cmd="$1"
  command -v flatpak >/dev/null || return 0
  ${cmd} --nosocket=pulseaudio
  ${cmd} --nofilesystem=xdg-run/pipewire-0
}

# Re-open Pulse/PipeWire. Lockdown (if still on) re-blocks Pulse on the next apply.
allow_one() {
  local cmd="$1"
  command -v flatpak >/dev/null || return 0
  ${cmd} --socket=pulseaudio
  ${cmd} --filesystem=xdg-run/pipewire-0
}

cmd_apply_system() {
  command -v flatpak >/dev/null || return 0
  wanted_on || return 0
  apply_one "flatpak override --system"
}

cmd_apply_user() {
  command -v flatpak >/dev/null || return 0
  wanted_on || return 0
  apply_one "flatpak override --user"
}

cmd_on() {
  as_root mkdir -p /etc/unwoke
  as_root rm -f "${STAMP_OFF}"
  as_root /usr/bin/bash /usr/libexec/unwoke/flatpak-record.sh apply-system
  cmd_apply_user
  echo "Flatpak record streams BLOCKED (Pulse socket + PipeWire). Speakers in native apps stay."
  echo "Revert: ujust set-flatpak-record off"
}

cmd_allow_system() {
  command -v flatpak >/dev/null || return 0
  allow_one "flatpak override --system"
}

cmd_allow_user() {
  command -v flatpak >/dev/null || return 0
  allow_one "flatpak override --user"
}

cmd_off() {
  as_root mkdir -p /etc/unwoke
  as_root touch "${STAMP_OFF}"
  as_root /usr/bin/bash /usr/libexec/unwoke/flatpak-record.sh allow-system || true
  cmd_allow_user || true
  if [[ -x /usr/libexec/unwoke/flatpak-lockdown.sh && ! -f /etc/unwoke/flatpak-lockdown.off ]]; then
    as_root /usr/bin/bash /usr/libexec/unwoke/flatpak-lockdown.sh apply-system || true
    /usr/libexec/unwoke/flatpak-lockdown.sh apply-user || true
  fi
  echo "Stamp ${STAMP_OFF} set. Pulse/PipeWire record is allowed again for Flatpaks."
  echo "Lockdown (if on) still cuts Pulse. Put the extra lock back: ujust set-flatpak-record on"
}

cmd_status() {
  if wanted_on; then
    echo "on (default; ${STAMP_OFF} absent)"
  else
    echo "off (${STAMP_OFF})"
  fi
}

case "${1:-status}" in
  on|enable|block) cmd_on ;;
  off|disable|allow) cmd_off ;;
  apply-system) cmd_apply_system ;;
  apply-user) cmd_apply_user ;;
  allow-system) cmd_allow_system ;;
  allow-user) cmd_allow_user ;;
  apply-boot)
    [[ "$(id -u)" -eq 0 ]] || exit 1
    cmd_apply_system
    ;;
  status) cmd_status ;;
  *)
    echo "usage: ujust set-flatpak-record on|off|status" >&2
    exit 2
    ;;
esac
