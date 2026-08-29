#!/usr/bin/env bash
# Same permission cuts as stock `ujust flatpak-permissions-lockdown`, plus
# --system so it is the image default. Toggle: /etc/unwoke/flatpak-lockdown.off
set -euo pipefail

STAMP_OFF="/etc/unwoke/flatpak-lockdown.off"

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    command -v run0 >/dev/null || { echo "need run0 (wheel user)" >&2; exit 1; }
    run0 "$@"
  fi
}

apply_one() {
  local cmd="$1"
  command -v flatpak >/dev/null || return 0

  local share socket device feature filesystem dangerous
  local session system
  local lists="/usr/share/unwoke/flatpak-lockdown-lists.sh"
  if [[ -f "${lists}" ]]; then
    # shellcheck disable=SC1090
    source "${lists}"
  else
    share=(network ipc)
    socket=(inherit-wayland-socket gpg-agent cups pcsc ssh-auth system-bus session-bus pulseaudio fallback-x11 x11)
    device=(all shm kvm input usb)
    feature=(per-app-dev-shm canbus bluetooth multiarch devel)
    filesystem=(home host-etc host)
    dangerous=("~/.bashrc" "~/.bash_profile" /home /var/home /var /media /run/media /run /mnt)
    session=(org.freedesktop.Flatpak)
    system=(org.freedesktop.systemd1)
  fi

  local i
  for i in "${share[@]}"; do ${cmd} --unshare="${i}"; done
  for i in "${socket[@]}"; do ${cmd} --nosocket="${i}"; done
  for i in "${device[@]}"; do ${cmd} --nodevice="${i}"; done
  for i in "${feature[@]}"; do ${cmd} --disallow="${i}"; done
  for i in "${filesystem[@]}"; do ${cmd} --nofilesystem="${i}"; done
  for i in "${dangerous[@]}"; do ${cmd} --nofilesystem="${i}"; done
  # Extra xdg/host-root cuts stock's lockdown just does not default. Not host-os
  # (harden-flatpak.sh needs host-os:ro for malloc). Revert with lockdown off.
  local extra_fs
  extra_fs=(host-root xdg-desktop xdg-documents xdg-download xdg-music xdg-pictures xdg-videos xdg-public-share xdg-templates xdg-cache xdg-config xdg-data)
  for i in "${extra_fs[@]}"; do ${cmd} --nofilesystem="${i}"; done
  for i in "${session[@]}"; do ${cmd} --no-talk-name="${i}"; done
  for i in "${system[@]}"; do ${cmd} --system-no-talk-name="${i}"; done
  ${cmd} --persist=.
  ${cmd} --socket=wayland --device=dri
  ${cmd} --talk-name=org.gnome.Software --talk-name=org.freedesktop.impl.portal.PermissionStore \
    com.github.tchx84.Flatseal || true
}

reapply_hardened_malloc() {
  # Our script, not /usr/libexec/secureblue/harden_flatpak.py.
  if [[ -x /usr/libexec/unwoke/harden-flatpak.sh ]]; then
    /usr/libexec/unwoke/harden-flatpak.sh || true
  fi
}

cmd_apply_system() {
  command -v flatpak >/dev/null || return 0
  apply_one "flatpak override --system"
}

cmd_apply_user() {
  command -v flatpak >/dev/null || return 0
  apply_one "flatpak override --user"
  reapply_hardened_malloc
}

cmd_reset_system() {
  command -v flatpak >/dev/null || return 0
  flatpak override --system --reset || true
}

cmd_reset_user() {
  local global="${HOME}/.local/share/flatpak/overrides/global"
  if [[ -f "${global}" ]]; then
    mv -f "${global}" "${global}.save"
  fi
  reapply_hardened_malloc
}

wanted_on() { [[ ! -f "${STAMP_OFF}" ]]; }

case "${1:-status}" in
  apply-system)
    wanted_on || exit 0
    cmd_apply_system
    ;;
  apply-user)
    wanted_on || exit 0
    cmd_apply_user
    ;;
  apply-boot)
    [[ "$(id -u)" -eq 0 ]] || exit 1
    wanted_on || exit 0
    cmd_apply_system
    ;;
  on)
    as_root mkdir -p /etc/unwoke
    as_root rm -f "${STAMP_OFF}"
    as_root /usr/bin/bash /usr/libexec/unwoke/flatpak-lockdown.sh apply-system
    cmd_apply_user
    echo "Flatpak permission lockdown ON (system + this user)."
    echo "Most Flatpaks will need permissions via Flatseal. Revert: ujust set-flatpak-lockdown off"
    ;;
  off)
    as_root mkdir -p /etc/unwoke
    as_root touch "${STAMP_OFF}"
    as_root /usr/bin/bash /usr/libexec/unwoke/flatpak-lockdown.sh reset-system-root
    cmd_reset_user
    if [[ -x /usr/libexec/unwoke/flatpak-record.sh ]]; then
      as_root /usr/libexec/unwoke/flatpak-record.sh apply-system
      /usr/libexec/unwoke/flatpak-record.sh apply-user || true
    fi
    echo "Flatpak permission lockdown OFF. Global user overrides saved as global.save if present."
    echo "Unwoke harden-flatpak.sh re-applied malloc preload. Record-block stays unless you also: ujust set-flatpak-record off"
    echo "Re-enable lockdown: ujust set-flatpak-lockdown on"
    ;;
  reset-system-root)
    cmd_reset_system
    ;;
  status)
    if wanted_on; then
      echo "on (default; ${STAMP_OFF} absent)"
    else
      echo "off (${STAMP_OFF})"
    fi
    ;;
  *)
    echo "usage: flatpak-lockdown.sh on|off|status|apply-boot|apply-user" >&2
    exit 2
    ;;
esac
