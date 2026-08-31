#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Play window: auto while a game runs. Login agent starts/stops it.
# Close Steam → restore. No typing. ujust play stop is optional.
# User-owned stamps only (no run0 in the agent). Does not flip SMT/mitigations.
set -euo pipefail

CFG="${XDG_CONFIG_HOME:-$HOME/.config}/unwoke"
STAMP="${CFG}/play-window.active"
SAVE="${CFG}/play-window.save"
ALLOW_SCX="${CFG}/play-scx.on"
DENY_SCX="${CFG}/play-scx.off"
SYS_STAMP="/etc/unwoke/play-window.active"
SYS_SCX="/etc/unwoke/play-scx.on"

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    command -v run0 >/dev/null || return 1
    run0 "$@"
  fi
}

scx_wanted() {
  [[ -f "${DENY_SCX}" ]] && return 1
  [[ -f "${ALLOW_SCX}" || -f "${SYS_SCX}" ]] && return 0
  command -v scxctl >/dev/null
}

game_running() {
  pgrep -x steam >/dev/null 2>&1 \
    || pgrep -f 'com.valvesoftware.Steam' >/dev/null 2>&1 \
    || pgrep -x gamescope >/dev/null 2>&1 \
    || pgrep -x lutris >/dev/null 2>&1
}

scx_stop() {
  command -v scxctl >/dev/null || return 0
  scxctl stop >/dev/null 2>&1 || true
}

scx_start() {
  scx_wanted || return 0
  command -v scxctl >/dev/null || return 0
  scxctl start --sched lavd --mode gaming >/dev/null 2>&1 \
    || scxctl start --sched lavd >/dev/null 2>&1 \
    || true
}

write_stamp() {
  mkdir -p "${CFG}"
  cat > "${STAMP}" <<EOF
# UNWOKE-SHIPPED-FIRST
started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
uid=${UID:-}
gamemode=1
scx=$(scx_wanted && echo 1 || echo 0)
session_ramdisk=0
session_ptrace=0
session_xwayland=0
EOF
}

active() { [[ -f "${STAMP}" || -f "${SYS_STAMP}" ]]; }

cmd_restore() {
  local talk="${1:-1}"
  scx_stop
  if [[ -f "${SAVE}" ]]; then
    # shellcheck disable=SC1090
    source "${SAVE}" || true
    if [[ -n "${PREV_PP:-}" ]] && command -v powerprofilesctl >/dev/null; then
      powerprofilesctl set "${PREV_PP}" >/dev/null 2>&1 || true
    fi
    rm -f "${SAVE}"
  fi
  rm -f "${STAMP}"
  if [[ -f "${SYS_STAMP}" ]]; then
    as_root rm -f "${SYS_STAMP}" 2>/dev/null || rm -f "${SYS_STAMP}" 2>/dev/null || true
  fi
  if [[ "${talk}" == "1" ]]; then
    echo "Play window closed. Locks are back. Optional check: ujust unwoke-test"
  fi
}

cmd_restore_boot() {
  # Root: wipe leftover system stamp. User agent handles ~/.config on login.
  [[ "$(id -u)" -eq 0 ]] || exit 0
  scx_stop
  rm -f "${SYS_STAMP}"
}

cmd_arm() {
  # Called when a game is detected. No prompts. No run0.
  if active && game_running; then
    return 0
  fi
  mkdir -p "${CFG}"
  local prev=""
  if command -v powerprofilesctl >/dev/null; then
    prev="$(powerprofilesctl get 2>/dev/null || true)"
    printf 'PREV_PP=%q\n' "${prev}" > "${SAVE}"
    powerprofilesctl set performance >/dev/null 2>&1 || true
  fi
  write_stamp
  systemctl --user start gamemoded.service >/dev/null 2>&1 || true
  scx_start
}

cmd_start() {
  cmd_arm
  echo "Play window ON (also automatic: just launch Steam)."
  echo "  GameMode: $(command -v gamemoderun >/dev/null && echo present || echo missing)"
  echo "  sched-ext: $(scx_wanted && echo allowed || echo off)"
  echo "Close the game. Restore is automatic. Manual: ujust play stop"
  local launch="${1:-}"
  if [[ "${launch}" == "steam" || "${launch}" == "--steam" ]]; then
    exec /usr/libexec/unwoke/play-steam.sh
  fi
}

cmd_agent() {
  # Login-long. Just click Steam. No TTY.
  mkdir -p "${CFG}"
  if active && ! game_running; then
    cmd_restore 0
  fi
  local was=0
  game_running && was=1
  while true; do
    if game_running; then
      if [[ "${was}" -eq 0 ]] || ! active; then
        cmd_arm
      fi
      was=1
    else
      if [[ "${was}" -eq 1 ]] || active; then
        cmd_restore 0
      fi
      was=0
    fi
    sleep 3
  done
}

cmd_scx_on() {
  mkdir -p "${CFG}"
  rm -f "${DENY_SCX}"
  touch "${ALLOW_SCX}"
  echo "sched-ext during play: on (also the default if scxctl is installed)."
}

cmd_scx_off() {
  mkdir -p "${CFG}"
  rm -f "${ALLOW_SCX}"
  touch "${DENY_SCX}"
  scx_stop
  echo "sched-ext during play: off. Put it back: ujust play scx on"
}

cmd_status() {
  if active; then
    echo "play-window: ACTIVE"
    [[ -f "${STAMP}" ]] && cat "${STAMP}"
  else
    echo "play-window: off (full overlay locks)"
  fi
  if game_running; then
    echo "game: running (restore is automatic when it exits)"
  else
    echo "game: none"
  fi
  echo "gamemoderun: $(command -v gamemoderun 2>/dev/null || echo missing)"
  echo "scx allowed: $(scx_wanted && echo yes || echo no)"
  echo "agent: just click Steam — no need to type play stop"
}

case "${1:-status}" in
  start) cmd_start "${2:-}" ;;
  steam) cmd_start steam ;;
  stop|end|restore) cmd_restore 1 ;;
  restore-boot|apply-boot) cmd_restore_boot ;;
  arm) cmd_arm ;;
  agent) cmd_agent ;;
  watch) cmd_agent ;;
  scx)
    case "${2:-status}" in
      on|enable|allow) cmd_scx_on ;;
      off|disable) cmd_scx_off ;;
      *) echo "scx allowed: $(scx_wanted && echo yes || echo no)" ;;
    esac
    ;;
  status) cmd_status ;;
  *)
    echo "usage: ujust play status|steam|stop|scx on|scx off" >&2
    echo "Normal: click Steam. The login agent restores when it exits." >&2
    exit 2
    ;;
esac
