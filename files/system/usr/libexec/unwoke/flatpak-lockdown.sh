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
  local session system names
  share=(network ipc)
  socket=(inherit-wayland-socket gpg-agent cups pcsc ssh-auth system-bus session-bus pulseaudio fallback-x11 x11)
  device=(all shm kvm input usb)
  feature=(per-app-dev-shm canbus bluetooth multiarch devel)
  filesystem=(home host-etc host)
  # shellcheck disable=SC2088
  dangerous=("~/.bashrc" "~/.bash_profile" /home /var/home /var /media /run/media /run /mnt)
  session=(
    org.xfce.ScreenSaver org.mate.ScreenSaver org.cinnamon.ScreenSaver
    org.gnome.ScreenSaver org.kde.kwalletd6 "org.gnome.Mutter.IdleMonitor.*"
    org.gnome.ControlCenter org.gnome.Settings org.gnome.SettingsDaemon.MediaKeys
    org.gnome.SessionManager org.gnome.Shell.Screenshot org.kde.kiod5
    org.kde.kwin.Screenshot org.kde.JobViewServer "org.gtk.vfs.*"
    org.freedesktop.secrets org.kde.kconfig.notify org.kde.kpasswdserver "org.kde.*"
    org.kde.StatusNotifierWatcher org.kde.kded6 org.kde.kpasswdserver6 org.kde.kiod6
    com.canonical.Unity org.freedesktop.Notifications org.freedesktop.FileManager1
    org.freedesktop.impl.portal.PermissionStore org.freedesktop.Flatpak
    com.canonical.AppMenu.Registrar org.kde.KGlobalSettings org.kde.kded5
    com.canonical.Unity.LauncherEntry org.kde.kwalletd5 org.gnome.SettingsDaemon
    org.a11y.Bus com.canonical.indicator.application org.freedesktop.ScreenSaver
    ca.desrt.dconf org.freedesktop.PowerManagement org.gnome.Software
    org.freedesktop.Tracker3.Writeback io.missioncenter.MissionCenter.Gatherer
  )
  system=(
    org.bluez org.freedesktop.home1 org.freedesktop.hostname1 org.freedesktop.import1
    org.freedesktop.locale1 org.freedesktop.LogControl1 org.freedesktop.machine1
    org.freedesktop.network1 org.freedesktop.oom1 org.freedesktop.portable1
    org.freedesktop.resolve1 org.freedesktop.sysupdate1 org.freedesktop.timesync1
    org.freedesktop.timedate1 org.freedesktop.systemd1 org.freedesktop.Avahi
    "org.freedesktop.Avahi.*" org.freedesktop.login1 org.freedesktop.NetworkManager
    org.freedesktop.UPower org.freedesktop.UDisks2 org.freedesktop.fwupd
  )

  local i
  for i in "${share[@]}"; do ${cmd} --unshare="${i}"; done
  for i in "${socket[@]}"; do ${cmd} --nosocket="${i}"; done
  for i in "${device[@]}"; do ${cmd} --nodevice="${i}"; done
  for i in "${feature[@]}"; do ${cmd} --disallow="${i}"; done
  for i in "${filesystem[@]}"; do ${cmd} --nofilesystem="${i}"; done
  for i in "${dangerous[@]}"; do ${cmd} --nofilesystem="${i}"; done
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
    echo "Flatpak permission lockdown OFF. Global user overrides saved as global.save if present."
    echo "Unwoke harden-flatpak.sh re-applied malloc preload. Re-enable: ujust set-flatpak-lockdown on"
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
