#!/usr/bin/env bash
# Webcam modules + V4L/ALSA capture nodes locked until ujust set-camera-mic on.
# Playback (speakers, USB headsets) is not blacklisted.
set -euo pipefail

ALLOW="/etc/unwoke/allow-camera-mic"
MOD_SRC="/usr/share/unwoke/modprobe-camera.conf"
MOD_DST="/etc/modprobe.d/unwoke-camera.conf"
UDEV_SRC="/usr/share/unwoke/udev-camera-mic.rules"
UDEV_DST="/etc/udev/rules.d/99-unwoke-camera-mic.rules"

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    command -v run0 >/dev/null || { echo "need run0 (wheel user)" >&2; exit 1; }
    run0 "$@"
  fi
}

wanted_lock() { [[ ! -f "${ALLOW}" ]]; }

reload_udev() {
  if command -v udevadm >/dev/null; then
    udevadm control --reload-rules || true
    udevadm trigger --subsystem-match=video4linux --subsystem-match=sound || true
  fi
}

cmd_apply_boot() {
  [[ "$(id -u)" -eq 0 ]] || exit 1
  mkdir -p /etc/modprobe.d /etc/udev/rules.d
  if wanted_lock; then
    [[ -f "${MOD_SRC}" ]] && cp -a "${MOD_SRC}" "${MOD_DST}"
    [[ -f "${UDEV_SRC}" ]] && cp -a "${UDEV_SRC}" "${UDEV_DST}"
  else
    rm -f "${MOD_DST}" "${UDEV_DST}"
  fi
  reload_udev
}

cmd_on() {
  as_root mkdir -p /etc/unwoke
  as_root touch "${ALLOW}"
  as_root /usr/bin/bash /usr/libexec/unwoke/camera-mic.sh apply-boot
  echo "Camera/mic ALLOWED. You may need to reload the webcam module or replug USB:"
  echo "  run0 modprobe uvcvideo"
  echo "Revert: ujust set-camera-mic off"
}

cmd_off() {
  as_root rm -f "${ALLOW}"
  as_root /usr/bin/bash /usr/libexec/unwoke/camera-mic.sh apply-boot
  echo "Camera/mic LOCKED (uvcvideo blacklisted; V4L and ALSA capture nodes mode 000)."
  echo "Speakers stay. Revert: ujust set-camera-mic on"
}

cmd_status() {
  if wanted_lock; then
    echo "off/locked (default — ${ALLOW} absent)"
  else
    echo "on/allowed (${ALLOW})"
  fi
}

case "${1:-status}" in
  on|enable|allow) cmd_on ;;
  off|disable|lock) cmd_off ;;
  apply-boot) cmd_apply_boot ;;
  status) cmd_status ;;
  *)
    echo "usage: ujust set-camera-mic on|off|status" >&2
    exit 2
    ;;
esac
