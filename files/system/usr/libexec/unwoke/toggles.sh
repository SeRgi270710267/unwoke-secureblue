#!/usr/bin/env bash
# Overlay toggles. Stock secureblue ujust commands still apply; this only
# covers extras we added (flavor, Brave Origin policies).
set -euo pipefail

HARDEN_SRC="/usr/share/unwoke/brave-hardening.json"
JITLESS_SRC="/usr/share/unwoke/brave-jitless.json"
POLICY_DIR="/etc/brave-origin/policies/managed"
HARDEN_DST="${POLICY_DIR}/10-unwoke-hardening.json"
JITLESS_DST="${POLICY_DIR}/20-unwoke-jitless.json"
OPT_OUT="/etc/unwoke/brave-hardening.off"
FLAVOR="brave-origin"
if [[ -f /usr/share/unwoke/flavor ]]; then
  FLAVOR="$(tr -d '[:space:]' < /usr/share/unwoke/flavor)"
fi

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

is_browserless() { [[ "${FLAVOR}" == "browserless" ]]; }

cmd_status() {
  echo "unwoke-secureblue (${FLAVOR})"
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
    ok "harden_userns enabled (unconfined apps cannot create userns)"
  else
    bad "harden_userns missing or disabled — run: ujust set-unconfined-userns off"
  fi

  if is_browserless; then
    ok "flavor: browserless (no image browser)"
    if command -v semodule >/dev/null && semodule -l 2>/dev/null | grep -qx unwoke_brave; then
      bad "unwoke_brave loaded — browserless must not add brave_t"
    else
      ok "no brave_t userns exception"
    fi
    if [[ -e /opt/brave.com/brave-origin/brave ]]; then
      bad "Brave Origin ELF present on a browserless image"
    else
      ok "no Brave Origin"
    fi
    if [[ -e /opt/brave.com/brave/brave ]]; then
      bad "full brave-browser is installed"
    else
      ok "no full brave-browser"
    fi
    info "Brave Origin policies: n/a"
    if [[ -f /etc/unwoke/allow-browsers ]]; then
      bad "allow-browsers ON — easy host browser installs are unlocked"
    else
      ok "allow-browsers OFF — ujust set-allow-browsers on ALLOW to unlock"
    fi
  else
    if command -v semodule >/dev/null && semodule -l 2>/dev/null | grep -qx unwoke_brave; then
      ok "unwoke_brave SELinux module loaded (Brave userns via brave_t)"
    else
      bad "unwoke_brave module not listed"
    fi
    if [[ -e /opt/brave.com/brave-origin/brave ]]; then
      ok "Brave Origin binary present (/opt/brave.com/brave-origin/brave)"
    else
      bad "Brave Origin ELF missing"
    fi
    if [[ -e /opt/brave.com/brave/brave ]]; then
      bad "full brave-browser is also installed; this overlay wants brave-origin only"
    fi
    if [[ -f "${HARDEN_DST}" ]] || [[ -f /usr/etc/brave-origin/policies/managed/10-unwoke-hardening.json && ! -f "${OPT_OUT}" ]]; then
      ok "Brave Origin managed hardening policy on (restart the browser after changes)"
    else
      info "Brave managed hardening policy off"
    fi
    if [[ -f "${JITLESS_DST}" ]]; then
      info "Brave JIT disabled (breaks some sites)"
    else
      info "Brave JIT allowed (default)"
    fi
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
  if is_browserless; then
    echo "Browserless: ujust set-allow-browsers on ALLOW"
  fi
}

cmd_audit() {
  cmd_status
  fail=0
  command -v semodule >/dev/null && semodule -l 2>/dev/null | grep -qx harden_userns || fail=1
  if is_browserless; then
    [[ ! -e /opt/brave.com/brave-origin/brave ]] || fail=1
    [[ ! -e /opt/brave.com/brave/brave ]] || fail=1
    if command -v semodule >/dev/null && semodule -l 2>/dev/null | grep -qx unwoke_brave; then
      fail=1
    fi
  else
    command -v semodule >/dev/null && semodule -l 2>/dev/null | grep -qx unwoke_brave || fail=1
    [[ -e /opt/brave.com/brave-origin/brave ]] || fail=1
    [[ ! -e /opt/brave.com/brave/brave ]] || fail=1
  fi
  if [[ -e /opt/brave.com ]] && find /opt/brave.com -xdev -perm -4000 -type f 2>/dev/null | grep -q .; then
    fail=1
  fi
  exit "${fail}"
}

need_origin() {
  if is_browserless; then
    echo "This image is browserless. Rebase to unwoke-*-silverblue / kinoite (no -browserless) for Brave Origin policies." >&2
    exit 1
  fi
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
  need_origin
  local action="${1:-status}"
  case "${action}" in
    on|enable)
      policy_on "${HARDEN_SRC}" "${HARDEN_DST}"
      as_root mkdir -p /etc/unwoke
      as_root rm -f "${OPT_OUT}"
      echo "Brave Origin hardening policy ON. Restart Brave Origin."
      ;;
    off|disable)
      policy_off "${HARDEN_DST}"
      as_root mkdir -p /etc/unwoke
      as_root touch "${OPT_OUT}"
      echo "Brave Origin hardening policy OFF. Restart Brave Origin."
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
  need_origin
  local action="${1:-status}"
  case "${action}" in
    on|enable)
      policy_on "${JITLESS_SRC}" "${JITLESS_DST}"
      echo "Brave Origin JavaScript JIT blocked. Some sites will break. Restart Brave Origin."
      ;;
    off|disable)
      policy_off "${JITLESS_DST}"
      echo "Brave Origin JavaScript JIT allowed. Restart Brave Origin."
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

confirm_allow() {
  local extra="${1:-}"
  if [[ "${extra}" == "ALLOW" ]]; then
    return 0
  fi
  if [[ -t 0 ]]; then
    echo "This unlocks easy host browser installs (Flatpak + rpm-ostree)."
    echo "A random Firefox/Chrome is usually worse than stock Trivalent."
    echo "Toolbox, brew, and AppImage are not blocked either way."
    echo "Type ALLOW to continue:"
    local ans=""
    read -r ans || true
    [[ "${ans}" == "ALLOW" ]] || { echo "aborted" >&2; exit 1; }
    return 0
  fi
  echo "usage: ujust set-allow-browsers on ALLOW" >&2
  exit 2
}

cmd_allow_browsers() {
  if ! is_browserless; then
    echo "This toggle is for -browserless images. Origin images already ship Brave Origin." >&2
    exit 1
  fi
  local action="${1:-status}"
  case "${action}" in
    on|enable)
      confirm_allow "${2:-}"
      as_root /usr/libexec/unwoke/browser-guard.sh lift
      /usr/libexec/unwoke/browser-guard.sh unmask-user || true
      echo "Host browser installs unlocked. Flathub CLI remote added."
      echo "This does not make the box as tight as stock secureblue + Trivalent."
      ;;
    off|disable)
      as_root /usr/libexec/unwoke/browser-guard.sh block
      /usr/libexec/unwoke/browser-guard.sh apply --user || true
      echo "Easy host browser installs blocked again. Already-installed browsers stay until you remove them."
      ;;
    status)
      /usr/libexec/unwoke/browser-guard.sh status
      ;;
    *)
      echo "usage: ujust set-allow-browsers on ALLOW|off|status" >&2
      exit 2
      ;;
  esac
}

usage() {
  echo "usage: toggles.sh status|audit|hardening|jitless|allow-browsers [on|off|status]" >&2
  exit 2
}

main="${1:-status}"
shift || true
case "${main}" in
  status) cmd_status ;;
  audit) cmd_audit ;;
  hardening) cmd_hardening "${1:-status}" ;;
  jitless) cmd_jitless "${1:-status}" ;;
  allow-browsers) cmd_allow_browsers "${1:-status}" "${2:-}" ;;
  *) usage ;;
esac
