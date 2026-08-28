#!/usr/bin/env bash
# Overlay toggles. Stock secureblue ujust commands still apply.
set -euo pipefail

HARDEN_SRC="/usr/share/unwoke/brave-hardening.json"
DEVICES_SRC="/usr/share/unwoke/brave-devices.json"
JITLESS_SRC="/usr/share/unwoke/brave-jitless.json"
EXT_SRC="/usr/share/unwoke/brave-extensions.json"
POLICY_DIR="/etc/brave-origin/policies/managed"
HARDEN_DST="${POLICY_DIR}/10-unwoke-hardening.json"
DEVICES_DST="${POLICY_DIR}/15-unwoke-devices.json"
JITLESS_DST="${POLICY_DIR}/20-unwoke-jitless.json"
EXT_DST="${POLICY_DIR}/30-unwoke-extensions.json"
HARDEN_OFF="/etc/unwoke/brave-hardening.off"
DEVICES_OFF="/etc/unwoke/brave-devices.off"
JITLESS_OFF="/etc/unwoke/brave-jitless.off"
EXT_OFF="/etc/unwoke/brave-extensions.off"
BUBBLE_STAMP="/etc/unwoke/brave-bubblejail"

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

need_origin() {
  if is_browserless; then
    echo "This image is browserless. Rebase to an Origin image (no -browserless) for Brave Origin policies." >&2
    exit 1
  fi
}

policy_on() {
  local src="$1" dst="$2" off="$3"
  as_root mkdir -p "${POLICY_DIR}" /etc/unwoke
  as_root cp -a "${src}" "${dst}"
  as_root rm -f "${off}"
}

policy_off() {
  local dst="$1" off="$2"
  as_root mkdir -p /etc/unwoke
  as_root rm -f "${dst}"
  as_root touch "${off}"
}

policy_status() {
  local dst="$1" off="$2"
  if [[ -f "${dst}" ]]; then
    echo "on (${dst})"
  elif [[ -f "${off}" ]]; then
    echo "off (${off})"
  else
    echo "off"
  fi
}

cmd_status() {
  echo "Unwoke SecureBlue (${FLAVOR})"
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

  echo "  -- theme --"
  if [[ -f /usr/share/backgrounds/unwoke/unwoke-desktop.jpg ]]; then
    ok "Unwoke wallpaper + lock screen"
  else
    info "Unwoke wallpaper not in this image yet"
  fi
  info "GNOME accent named blue; GTK #3b6cff; KDE 59,108,255"
  echo "  -- remotes / lockdown --"
  if [[ -x /usr/libexec/unwoke/flathub.sh ]]; then
    /usr/libexec/unwoke/flathub.sh status | while IFS= read -r line; do info "flathub ${line}"; done
  fi
  if [[ -x /usr/libexec/unwoke/flatpak-lockdown.sh ]]; then
    info "flatpak-lockdown: $(/usr/libexec/unwoke/flatpak-lockdown.sh status)"
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
    info "brave_t is fat (unconfined-like). A tight jail is not shipped — Origin updates would break it, and it would still not be Trivalent."
    if [[ -e /opt/brave.com/brave-origin/brave ]]; then
      ok "Brave Origin binary present (/opt/brave.com/brave-origin/brave)"
    else
      bad "Brave Origin ELF missing"
    fi
    if [[ -e /opt/brave.com/brave/brave ]]; then
      bad "full brave-browser is also installed; this overlay wants brave-origin only"
    fi
    if [[ -f "${HARDEN_DST}" ]] || [[ -f /usr/etc/brave-origin/policies/managed/10-unwoke-hardening.json && ! -f "${HARDEN_OFF}" ]]; then
      ok "Brave hardening pack on (HTTPS/metrics/autofill/passwords)"
    else
      info "Brave hardening pack off — ujust set-brave-hardening on"
    fi
    if [[ -f "${DEVICES_DST}" ]] || [[ -f /usr/etc/brave-origin/policies/managed/15-unwoke-devices.json && ! -f "${DEVICES_OFF}" ]]; then
      ok "Brave device pack on (USB/BT/serial/camera/mic/geo blocked)"
    else
      info "Brave device pack off — ujust set-brave-devices on"
    fi
    if [[ -f "${JITLESS_DST}" ]] || [[ -f /usr/etc/brave-origin/policies/managed/20-unwoke-jitless.json && ! -f "${JITLESS_OFF}" ]]; then
      ok "Brave JIT blocked (some sites break) — ujust set-brave-jitless off"
    else
      info "Brave JIT allowed — ujust set-brave-jitless on"
    fi
    if [[ -f "${EXT_DST}" ]] || [[ -f /usr/etc/brave-origin/policies/managed/30-unwoke-extensions.json && ! -f "${EXT_OFF}" ]]; then
      ok "Brave extension installs blocked — ujust set-brave-extensions allow"
    else
      info "Brave extension installs allowed — ujust set-brave-extensions block"
    fi
    if [[ -f "${BUBBLE_STAMP}" ]]; then
      info "Brave Bubblejail wanted (${BUBBLE_STAMP}) — desktop launcher jails if the instance exists"
    else
      info "Brave Bubblejail off (default) — ujust set-brave-bubblejail on"
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
  echo "Toggles (all reversible):"
  echo "  ujust set-flathub verified|full|off"
  echo "  ujust set-flatpak-lockdown on|off"
  if is_browserless; then
    echo "  ujust set-allow-browsers on ALLOW|off"
  else
    echo "  ujust set-brave-hardening on|off"
    echo "  ujust set-brave-devices on|off"
    echo "  ujust set-brave-jitless on|off"
    echo "  ujust set-brave-extensions block|allow"
    echo "  ujust set-brave-bubblejail on|off"
  fi
  echo "Stock: ujust set-unconfined-userns  ujust set-kargs-hardening  ujust audit-secureblue"
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

cmd_pack() {
  need_origin
  local name="$1" src="$2" dst="$3" off="$4" action="${5:-status}"
  case "${action}" in
    on|enable|block)
      policy_on "${src}" "${dst}" "${off}"
      echo "${name} ON. Restart Brave Origin."
      ;;
    off|disable|allow)
      policy_off "${dst}" "${off}"
      echo "${name} OFF. Restart Brave Origin."
      ;;
    status)
      policy_status "${dst}" "${off}"
      ;;
    *)
      echo "usage: on|off|status" >&2
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
      echo "Host browser installs unlocked."
      echo "Flathub follows ujust set-flathub (default verified, not full)."
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

cmd_bubblejail() {
  need_origin
  local action="${1:-status}"
  case "${action}" in
    on|enable)
      command -v bubblejail >/dev/null || {
        echo "bubblejail is not on this image (stock secureblue desktop images ship it)." >&2
        exit 1
      }
      if ! bubblejail list 2>/dev/null | grep -qx brave-origin; then
        bubblejail create --profile chromium brave-origin \
          || bubblejail create --desktop-entry /usr/share/applications/brave-origin.desktop brave-origin \
          || bubblejail create brave-origin \
          || { echo "bubblejail create failed. Leave it off." >&2; exit 1; }
      fi
      as_root mkdir -p /etc/unwoke
      as_root touch "${BUBBLE_STAMP}"
      echo "Bubblejail ON for the Brave Origin desktop launcher (this user needs the instance; it was created)."
      echo "GPU/PipeWire/portals may break. Revert: ujust set-brave-bubblejail off"
      echo "Restart Brave Origin."
      ;;
    off|disable)
      as_root rm -f "${BUBBLE_STAMP}"
      echo "Bubblejail OFF. Launcher runs /opt/brave.com/brave-origin/brave directly."
      echo "The bubblejail instance was left in place; delete it yourself if you want."
      ;;
    status)
      if [[ -f "${BUBBLE_STAMP}" ]]; then
        echo "on (${BUBBLE_STAMP})"
      else
        echo "off (default)"
      fi
      ;;
    *)
      echo "usage: ujust set-brave-bubblejail on|off|status" >&2
      exit 2
      ;;
  esac
}

cmd_apply_boot() {
  [[ "$(id -u)" -eq 0 ]] || { echo "apply-boot needs root" >&2; exit 1; }
  mkdir -p /etc/unwoke
  if is_browserless; then
    echo "unwoke: browserless — no Origin policies"
    if [[ ! -f /etc/unwoke/flathub ]]; then
      printf 'off\n' > /etc/unwoke/flathub
    fi
    if [[ -x /usr/libexec/unwoke/flathub.sh ]]; then
      /usr/libexec/unwoke/flathub.sh apply-boot || true
    fi
  else
    mkdir -p "${POLICY_DIR}"
    [[ -f "${HARDEN_OFF}" ]] || cp -a "${HARDEN_SRC}" "${HARDEN_DST}" || true
    [[ -f "${DEVICES_OFF}" ]] || cp -a "${DEVICES_SRC}" "${DEVICES_DST}" || true
    [[ -f "${JITLESS_OFF}" ]] || cp -a "${JITLESS_SRC}" "${JITLESS_DST}" || true
    [[ -f "${EXT_OFF}" ]] || cp -a "${EXT_SRC}" "${EXT_DST}" || true
    if [[ ! -f /etc/unwoke/flathub ]]; then
      printf 'verified\n' > /etc/unwoke/flathub
    fi
    if [[ -x /usr/libexec/unwoke/flathub.sh ]]; then
      /usr/libexec/unwoke/flathub.sh apply-boot || true
    fi
  fi
  if [[ -x /usr/libexec/unwoke/flatpak-lockdown.sh ]]; then
    /usr/libexec/unwoke/flatpak-lockdown.sh apply-boot || true
  fi
}

cmd_apply_user() {
  if [[ -x /usr/libexec/unwoke/flatpak-lockdown.sh ]]; then
    /usr/libexec/unwoke/flatpak-lockdown.sh apply-user || true
  fi
  if [[ -x /usr/libexec/unwoke/theme.sh ]]; then
    /usr/libexec/unwoke/theme.sh apply-user-once || true
  fi
}

usage() {
  echo "usage: toggles.sh status|audit|hardening|devices|jitless|extensions|allow-browsers|flathub|lockdown|bubblejail|apply-boot|apply-user" >&2
  exit 2
}

main="${1:-status}"
shift || true
case "${main}" in
  status) cmd_status ;;
  audit) cmd_audit ;;
  hardening) cmd_pack "Brave hardening pack" "${HARDEN_SRC}" "${HARDEN_DST}" "${HARDEN_OFF}" "${1:-status}" ;;
  devices) cmd_pack "Brave device pack" "${DEVICES_SRC}" "${DEVICES_DST}" "${DEVICES_OFF}" "${1:-status}" ;;
  jitless) cmd_pack "Brave JIT-less" "${JITLESS_SRC}" "${JITLESS_DST}" "${JITLESS_OFF}" "${1:-status}" ;;
  extensions)
    case "${1:-status}" in
      block|on|enable) cmd_pack "Brave extension block" "${EXT_SRC}" "${EXT_DST}" "${EXT_OFF}" on ;;
      allow|off|disable) cmd_pack "Brave extension block" "${EXT_SRC}" "${EXT_DST}" "${EXT_OFF}" off ;;
      status) cmd_pack "Brave extension block" "${EXT_SRC}" "${EXT_DST}" "${EXT_OFF}" status ;;
      *) echo "usage: ujust set-brave-extensions block|allow|status" >&2; exit 2 ;;
    esac
    ;;
  allow-browsers) cmd_allow_browsers "${1:-status}" "${2:-}" ;;
  flathub) exec /usr/libexec/unwoke/flathub.sh "${1:-status}" ;;
  lockdown) exec /usr/libexec/unwoke/flatpak-lockdown.sh "${1:-status}" ;;
  bubblejail) cmd_bubblejail "${1:-status}" ;;
  apply-boot) cmd_apply_boot ;;
  apply-user) cmd_apply_user ;;
  *) usage ;;
esac
