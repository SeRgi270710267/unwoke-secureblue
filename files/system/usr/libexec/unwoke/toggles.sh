#!/usr/bin/env bash
# Overlay toggles. Stock secureblue ujust commands still apply; this only
# covers origin Brave extras we added.
set -euo pipefail

HARDEN_SRC="/usr/share/unwoke/brave-hardening.json"
JITLESS_SRC="/usr/share/unwoke/brave-jitless.json"
POLICY_DIR="/etc/brave/policies/managed"
HARDEN_DST="${POLICY_DIR}/10-unwoke-hardening.json"
JITLESS_DST="${POLICY_DIR}/20-unwoke-jitless.json"
OPT_OUT="/etc/unwoke/brave-hardening.off"

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    command -v run0 >/dev/null || { echo "need run0 (wheel user)" >&2; exit 1; }
    run0 "$@"
  fi
}

ok() { printf '  [ok]  %s\n' "$*"; }
bad() { printf '  [NO]  %s\n' "$*"; }
info() { printf '  [--]  %s\n' "$*"; }

cmd_status() {
  echo "unwoke-secureblue"
  if [[ -f /usr/share/ublue-os/image-info.json ]]; then
    info "image-info: $(tr -d '\n' < /usr/share/ublue-os/image-info.json | head -c 200)"
  fi
  if command -v rpm-ostree >/dev/null; then
    info "origin: $(rpm-ostree status --json 2>/dev/null | python3 -c 'import json,sys
j=json.load(sys.stdin)
for d in j.get("deployments") or []:
    if d.get("booted"):
        print(d.get("origin") or d.get("container-image-reference") or "?")
        break' 2>/dev/null || echo unknown)"
  fi

  if command -v semodule >/dev/null && semodule -l 2>/dev/null | grep -qx harden_userns; then
    ok "harden_userns enabled (other apps cannot create userns)"
  else
    bad "harden_userns missing or disabled — run: ujust set-unconfined-userns off"
  fi
  if command -v semodule >/dev/null && semodule -l 2>/dev/null | grep -qx unwoke_brave; then
    ok "unwoke_brave SELinux module loaded (Brave userns via brave_t)"
  else
    bad "unwoke_brave module not listed"
  fi
  if [[ -e /opt/brave.com/brave/brave ]]; then
    ok "origin Brave binary present"
  else
    bad "Brave ELF missing"
  fi
  if [[ -f "${HARDEN_DST}" ]] || [[ -f /usr/etc/brave/policies/managed/10-unwoke-hardening.json && ! -f "${OPT_OUT}" ]]; then
    ok "Brave managed hardening policy on (restart Brave after changes)"
  else
    info "Brave managed hardening policy off"
  fi
  if [[ -f "${JITLESS_DST}" ]]; then
    info "Brave JIT disabled (breaks some sites)"
  else
    info "Brave JIT allowed (default)"
  fi
  if command -v rpm >/dev/null && rpm -q gnome-software >/dev/null 2>&1; then
    bad "gnome-software is installed"
  else
    ok "no GNOME Software"
  fi
  if command -v rpm >/dev/null && rpm -q plasma-discover >/dev/null 2>&1; then
    bad "plasma-discover is installed"
  else
    ok "no Plasma Discover"
  fi
  if [[ -e /opt/brave.com ]] && find /opt/brave.com -xdev -perm -4000 -type f 2>/dev/null | grep -q .; then
    bad "SUID files under /opt/brave.com"
  else
    ok "no SUID under /opt/brave.com"
  fi
  echo
  echo "Stock secureblue toggles still work, e.g.:"
  echo "  ujust set-unconfined-userns   ujust set-kargs-hardening"
  echo "  ujust audit-secureblue        ujust set-ptrace"
}

cmd_audit() {
  cmd_status
  fail=0
  command -v semodule >/dev/null && semodule -l 2>/dev/null | grep -qx harden_userns || fail=1
  command -v semodule >/dev/null && semodule -l 2>/dev/null | grep -qx unwoke_brave || fail=1
  [[ -e /opt/brave.com/brave/brave ]] || fail=1
  if [[ -e /opt/brave.com ]] && find /opt/brave.com -xdev -perm -4000 -type f 2>/dev/null | grep -q .; then
    fail=1
  fi
  exit "${fail}"
}

policy_on() {
  local src="$1" dst="$2"
  as_root mkdir -p "${POLICY_DIR}"
  as_root cp -a "${src}" "${dst}"
}

policy_off() {
  local dst="$1"
  as_root rm -f "${dst}"
}

cmd_hardening() {
  local action="${1:-status}"
  case "${action}" in
    on|enable)
      policy_on "${HARDEN_SRC}" "${HARDEN_DST}"
      as_root mkdir -p /etc/unwoke
      as_root rm -f "${OPT_OUT}"
      echo "Brave hardening policy ON. Restart Brave."
      ;;
    off|disable)
      policy_off "${HARDEN_DST}"
      as_root mkdir -p /etc/unwoke
      as_root touch "${OPT_OUT}"
      echo "Brave hardening policy OFF. Restart Brave."
      ;;
    status)
      if [[ -f "${HARDEN_DST}" ]]; then
        echo "on (${HARDEN_DST})"
      else
        echo "off"
      fi
      ;;
    *)
      echo "usage: ujust set-brave-hardening on|off|status" >&2
      exit 2
      ;;
  esac
}

cmd_jitless() {
  local action="${1:-status}"
  case "${action}" in
    on|enable)
      policy_on "${JITLESS_SRC}" "${JITLESS_DST}"
      echo "Brave JavaScript JIT blocked. Some sites will break. Restart Brave."
      ;;
    off|disable)
      policy_off "${JITLESS_DST}"
      echo "Brave JavaScript JIT allowed. Restart Brave."
      ;;
    status)
      if [[ -f "${JITLESS_DST}" ]]; then
        echo "on (${JITLESS_DST})"
      else
        echo "off"
      fi
      ;;
    *)
      echo "usage: ujust set-brave-jitless on|off|status" >&2
      exit 2
      ;;
  esac
}

usage() {
  echo "usage: toggles.sh status|audit|hardening|jitless [on|off|status]" >&2
  exit 2
}

main="${1:-status}"
shift || true
case "${main}" in
  status) cmd_status ;;
  audit) cmd_audit ;;
  hardening) cmd_hardening "${1:-status}" ;;
  jitless) cmd_jitless "${1:-status}" ;;
  *) usage ;;
esac
