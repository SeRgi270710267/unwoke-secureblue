#!/usr/bin/env bash
# Homebrew off by default (stock secureblue ships it). ujust set-brew on|off|status
set -euo pipefail

ALLOW="/etc/unwoke/allow-brew"
UNITS=(brew-setup.service brew-update.timer brew-upgrade.timer brew-update.service brew-upgrade.service)

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    command -v run0 >/dev/null || { echo "need run0 (wheel user)" >&2; exit 1; }
    run0 "$@"
  fi
}

wanted_off() { [[ ! -f "${ALLOW}" ]]; }

disable_units() {
  local u
  for u in "${UNITS[@]}"; do
    systemctl disable --now "$u" >/dev/null 2>&1 || true
    systemctl mask "$u" >/dev/null 2>&1 || true
  done
}

enable_units() {
  local u
  for u in "${UNITS[@]}"; do
    systemctl unmask "$u" >/dev/null 2>&1 || true
  done
  systemctl enable --now brew-setup.service >/dev/null 2>&1 || true
  systemctl enable brew-update.timer brew-upgrade.timer >/dev/null 2>&1 || true
}

patch_uupd() {
  local cfg="/etc/uupd/config.json"
  command -v python3 >/dev/null || return 0
  mkdir -p /etc/uupd
  local disable="$1"
  python3 - "$cfg" "$disable" <<'PY' || true
import json, os, sys
path, disable = sys.argv[1], sys.argv[2].lower() == "true"
data = {}
if os.path.isfile(path):
    try:
        data = json.load(open(path, encoding="utf-8"))
    except Exception:
        data = {}
data.setdefault("modules", {}).setdefault("brew", {})["disable"] = disable
open(path, "w", encoding="utf-8").write(json.dumps(data, indent=2) + "\n")
PY
}

cmd_apply_boot() {
  [[ "$(id -u)" -eq 0 ]] || exit 1
  if wanted_off; then
    disable_units
    patch_uupd true
  else
    enable_units
    patch_uupd false
  fi
}

cmd_on() {
  as_root mkdir -p /etc/unwoke
  as_root touch "${ALLOW}"
  as_root /usr/bin/bash /usr/libexec/unwoke/brew.sh apply-boot
  echo "Homebrew ON (stock-like). Open a new shell. Revert: ujust set-brew off"
}

cmd_off() {
  as_root rm -f "${ALLOW}"
  as_root /usr/bin/bash /usr/libexec/unwoke/brew.sh apply-boot
  echo "Homebrew OFF. brew is not on PATH; brew-setup/update timers masked. Revert: ujust set-brew on"
}

cmd_status() {
  if wanted_off; then
    echo "off (default; tighter than stock — ${ALLOW} absent)"
  else
    echo "on (${ALLOW})"
  fi
}

case "${1:-status}" in
  on|enable) cmd_on ;;
  off|disable) cmd_off ;;
  apply-boot) cmd_apply_boot ;;
  status) cmd_status ;;
  *)
    echo "usage: ujust set-brew on|off|status" >&2
    exit 2
    ;;
esac
