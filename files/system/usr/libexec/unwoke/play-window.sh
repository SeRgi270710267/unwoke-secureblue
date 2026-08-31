#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Play window: CachyOS-like session (GameMode + optional sched-ext) while a
# game runs. On exit, crash, or next boot: full overlay locks again.
# Does not flip SMT, mitigations, SELinux, harden_userns, or global lockdown.
# Does not silent-enable ptrace / Xwayland / ramdisk-exec.
set -euo pipefail

STAMP="/etc/unwoke/play-window.active"
ALLOW_SCX="/etc/unwoke/play-scx.on"
WATCH_PID="/run/user/${UID:-0}/unwoke-play-watch.pid"

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    command -v run0 >/dev/null || { echo "need run0 (wheel user)" >&2; return 1; }
    run0 "$@"
  fi
}

game_running() {
  pgrep -x steam >/dev/null 2>&1 \
    || pgrep -f 'com.valvesoftware.Steam' >/dev/null 2>&1 \
    || pgrep -x gamescope >/dev/null 2>&1 \
    || pgrep -x lutris >/dev/null 2>&1
}

scx_stop() {
  command -v scxctl >/dev/null || return 0
  scxctl stop >/dev/null 2>&1 || as_root scxctl stop >/dev/null 2>&1 || true
}

scx_start() {
  [[ -f "${ALLOW_SCX}" ]] || return 0
  command -v scxctl >/dev/null || {
    echo "sched-ext tools not installed. Layer scx-scheds + scx-tools yourself if you want that CachyOS switch. Kernel stays stock."
    return 0
  }
  # Session only. Never systemctl enable a gaming scheduler.
  scxctl start --sched lavd --mode gaming 2>/dev/null \
    || scxctl start --sched lavd 2>/dev/null \
    || as_root scxctl start --sched lavd --mode gaming 2>/dev/null \
    || echo "scxctl start failed (kernel may lack CONFIG_SCHED_CLASS_EXT). Play window continues with GameMode only."
}

write_stamp() {
  as_root mkdir -p /etc/unwoke
  as_root tee "${STAMP}" >/dev/null <<EOF
# UNWOKE-SHIPPED-FIRST
started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
uid=${UID:-}
gamemode=1
scx=$([[ -f "${ALLOW_SCX}" ]] && echo 1 || echo 0)
# session-only extra locks stay 0 unless a future wizard sets them
session_ramdisk=0
session_ptrace=0
session_xwayland=0
EOF
}

clear_stamp() {
  as_root rm -f "${STAMP}"
}

cmd_restore() {
  scx_stop
  clear_stamp
  echo "Play window closed. Overlay locks are the ones you had before (apply-boot + no session extras)."
  echo "Prove: ujust unwoke-test"
}

cmd_restore_boot() {
  [[ "$(id -u)" -eq 0 ]] || exit 1
  scx_stop
  rm -f "${STAMP}"
}

cmd_start() {
  if [[ -f "${STAMP}" ]] && game_running; then
    echo "Play window already live. End: ujust play stop"
    cmd_status
    return 0
  fi
  if [[ -f "${STAMP}" ]] && ! game_running; then
    echo "Stale play stamp with no game — restoring first (fail-closed)."
    cmd_restore
  fi
  write_stamp
  if command -v systemctl >/dev/null; then
    systemctl --user start gamemoded.service 2>/dev/null || true
  fi
  scx_start
  echo "Play window ON."
  echo "  GameMode: $(command -v gamemoderun >/dev/null && echo 'host binary present' || echo 'MISSING — rebase after overlay bake')"
  echo "  sched-ext: $([[ -f "${ALLOW_SCX}" ]] && echo 'allowed this session' || echo 'off — ujust play scx on')"
  echo "Does not turn on ptrace, Xwayland, temp exec, Bluetooth, or global lockdown."
  echo "Those stay whatever you answered in ujust install-steam."
  echo "When you close Steam/the game: ujust play stop   (or this watcher)."
  local launch="${1:-}"
  if [[ "${launch}" == "steam" || "${launch}" == "--steam" ]]; then
    if command -v flatpak >/dev/null && flatpak info com.valvesoftware.Steam >/dev/null 2>&1; then
      if command -v gamemoderun >/dev/null; then
        nohup gamemoderun flatpak run com.valvesoftware.Steam >/dev/null 2>&1 &
      else
        nohup flatpak run com.valvesoftware.Steam >/dev/null 2>&1 &
      fi
    elif command -v steam >/dev/null; then
      if command -v gamemoderun >/dev/null; then
        nohup gamemoderun steam >/dev/null 2>&1 &
      else
        nohup steam >/dev/null 2>&1 &
      fi
    else
      echo "Steam not installed. ujust install-steam first."
    fi
  fi
  cmd_watch_bg
}

cmd_watch_bg() {
  mkdir -p "$(dirname "${WATCH_PID}")" 2>/dev/null || true
  if [[ -f "${WATCH_PID}" ]] && kill -0 "$(cat "${WATCH_PID}" 2>/dev/null)" 2>/dev/null; then
    return 0
  fi
  nohup /usr/bin/bash /usr/libexec/unwoke/play-window.sh watch >/dev/null 2>&1 &
  echo $! > "${WATCH_PID}" 2>/dev/null || true
}

cmd_watch() {
  # Wait until a game appears, then until it is gone, then restore.
  local i=0
  while ! game_running; do
    i=$((i + 1))
    [[ "${i}" -lt 120 ]] || {
      echo "No game started in time. Restoring."
      cmd_restore
      rm -f "${WATCH_PID}"
      exit 0
    }
    sleep 2
  done
  while game_running; do
    sleep 5
  done
  cmd_restore
  rm -f "${WATCH_PID}"
}

cmd_scx_on() {
  as_root mkdir -p /etc/unwoke
  as_root touch "${ALLOW_SCX}"
  echo "sched-ext gaming scheduler ALLOWED during play windows. Revert: ujust play scx off"
  echo "Needs scxctl on PATH (Fedora scx-scheds). Not baked; extra origin if you layer COPR."
  echo "Stop still unloads it. Default kernel scheduler returns."
}

cmd_scx_off() {
  as_root rm -f "${ALLOW_SCX}"
  scx_stop
  echo "sched-ext during play: off (default)."
}

cmd_status() {
  if [[ -f "${STAMP}" ]]; then
    echo "play-window: ACTIVE"
    cat "${STAMP}" 2>/dev/null || true
    if game_running; then
      echo "game: running"
    else
      echo "game: none (stale — ujust play stop)"
    fi
  else
    echo "play-window: off (full overlay locks)"
  fi
  echo "gamemoderun: $(command -v gamemoderun 2>/dev/null || echo missing)"
  echo "scx allowed: $([[ -f "${ALLOW_SCX}" ]] && echo yes || echo no)"
  echo "scxctl: $(command -v scxctl 2>/dev/null || echo missing)"
}

case "${1:-status}" in
  start) cmd_start "${2:-}" ;;
  steam) cmd_start steam ;;
  stop|end|restore) cmd_restore ;;
  restore-boot|apply-boot) cmd_restore_boot ;;
  watch) cmd_watch ;;
  scx)
    case "${2:-status}" in
      on|enable|allow) cmd_scx_on ;;
      off|disable) cmd_scx_off ;;
      *) echo "scx allowed: $([[ -f "${ALLOW_SCX}" ]] && echo yes || echo no)" ;;
    esac
    ;;
  status) cmd_status ;;
  *)
    echo "usage: ujust play start|steam|stop|status|scx on|scx off" >&2
    exit 2
    ;;
esac
