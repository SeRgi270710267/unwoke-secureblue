#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Overlay toggles. Stock secureblue ujust commands still apply.
set -euo pipefail

HARDEN_SRC="/usr/share/unwoke/brave-hardening.json"
DEVICES_SRC="/usr/share/unwoke/brave-devices.json"
JITLESS_SRC="/usr/share/unwoke/brave-jitless.json"
EXT_SRC="/usr/share/unwoke/brave-extensions.json"
ISO_SRC="/usr/share/unwoke/brave-isolation.json"
SANDBOX_SRC="/usr/share/unwoke/brave-sandbox.json"
DEVTOOLS_SRC="/usr/share/unwoke/brave-devtools.json"

HARDEN_FILE="10-unwoke-hardening.json"
DEVICES_FILE="15-unwoke-devices.json"
JITLESS_FILE="20-unwoke-jitless.json"
EXT_FILE="30-unwoke-extensions.json"
ISO_FILE="40-unwoke-isolation.json"
SANDBOX_FILE="50-unwoke-sandbox.json"
DEVTOOLS_FILE="60-unwoke-devtools.json"

HARDEN_OFF="/etc/unwoke/brave-hardening.off"
DEVICES_OFF="/etc/unwoke/brave-devices.off"
JITLESS_OFF="/etc/unwoke/brave-jitless.off"
EXT_OFF="/etc/unwoke/brave-extensions.off"
ISO_OFF="/etc/unwoke/brave-isolation.off"
SANDBOX_OFF="/etc/unwoke/brave-sandbox.off"
DEVTOOLS_OFF="/etc/unwoke/brave-devtools.off"
BUBBLE_OFF="/etc/unwoke/brave-bubblejail.off"
NET_OFF="/etc/unwoke/trivalent-network-sandbox.off"
REF_OFF="/etc/unwoke/trivalent-referrers.off"

ISO_CONF_SRC="/usr/share/unwoke/trivalent-isolation.conf"
NET_SRC="/usr/share/unwoke/trivalent-network-sandbox.conf"
REF_SRC="/usr/share/unwoke/trivalent-referrers.conf"
TRIV_CONF_D="/etc/trivalent/trivalent.conf.d"
ISO_CONF="${TRIV_CONF_D}/40-unwoke-isolation.conf"
NET_CONF="${TRIV_CONF_D}/50-unwoke-network-sandbox.conf"
REF_CONF="${TRIV_CONF_D}/60-unwoke-referrers.conf"

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
is_origin() { [[ "${FLAVOR}" == "brave-origin" ]]; }
is_trivalent() { [[ "${FLAVOR}" == "trivalent" ]]; }
has_browser_policies() { is_origin || is_trivalent; }

browser_name() {
  if is_trivalent; then
    echo "Trivalent"
  else
    echo "Brave Origin"
  fi
}

need_browser_policies() {
  if is_browserless; then
    echo "This image is browserless. Rebase to Origin (no suffix) or *-trivalent for browser policy packs." >&2
    exit 1
  fi
}

need_origin() {
  if ! is_origin; then
    echo "Bubblejail wrapping is Origin-only. Stock Trivalent already ships its own sandbox; their FAQ says not to Bubblejail it." >&2
    exit 1
  fi
}

need_trivalent() {
  if ! is_trivalent; then
    echo "This toggle is for -trivalent images (Trivalent conf.d / extra flags)." >&2
    exit 1
  fi
}

policy_dirs() {
  if is_trivalent; then
    printf '%s\n' /etc/trivalent/policies/managed /etc/chromium/policies/managed
  else
    printf '%s\n' /etc/brave-origin/policies/managed
  fi
}

vendor_has() {
  local file="$1"
  if is_trivalent; then
    [[ -f "/usr/etc/trivalent/policies/managed/${file}" ]] \
      || [[ -f "/usr/etc/chromium/policies/managed/${file}" ]]
  else
    [[ -f "/usr/etc/brave-origin/policies/managed/${file}" ]]
  fi
}

any_dst() {
  local file="$1" d
  while IFS= read -r d; do
    [[ -n "${d}" && -f "${d}/${file}" ]] && return 0
  done < <(policy_dirs)
  return 1
}

policy_on() {
  local src="$1" file="$2" off="$3" d
  as_root mkdir -p /etc/unwoke
  while IFS= read -r d; do
    [[ -n "${d}" ]] || continue
    as_root mkdir -p "${d}"
    as_root python3 /usr/libexec/unwoke/mark-check.py --install-policy \
      "${src}" "${d}/${file}"
  done < <(policy_dirs)
  as_root rm -f "${off}"
}

policy_off() {
  local file="$1" off="$2" d
  as_root mkdir -p /etc/unwoke
  while IFS= read -r d; do
    [[ -n "${d}" ]] || continue
    as_root rm -f "${d}/${file}"
  done < <(policy_dirs)
  as_root touch "${off}"
}

policy_status() {
  local file="$1" off="$2"
  if any_dst "${file}"; then
    echo "on"
  elif [[ -f "${off}" ]]; then
    echo "off (${off})"
  elif vendor_has "${file}"; then
    echo "on (image default)"
  else
    echo "off"
  fi
}

policy_is_on() {
  local file="$1" off="$2"
  [[ -f "${off}" ]] && return 1
  any_dst "${file}" && return 0
  vendor_has "${file}"
}

conf_on() {
  local src="$1" dst="$2" off="$3"
  as_root mkdir -p /etc/unwoke "$(dirname "${dst}")"
  as_root cp -a "${src}" "${dst}"
  as_root rm -f "${off}"
}

conf_off() {
  local dst="$1" off="$2"
  as_root mkdir -p /etc/unwoke
  as_root rm -f "${dst}"
  as_root touch "${off}"
}

conf_status() {
  local dst="$1" off="$2" vendor="$3"
  if [[ -f "${dst}" ]]; then
    echo "on (${dst})"
  elif [[ -f "${off}" ]]; then
    echo "off (${off})"
  elif [[ -f "${vendor}" ]]; then
    echo "on (image default)"
  else
    echo "off"
  fi
}

conf_is_on() {
  local dst="$1" off="$2" vendor="$3"
  [[ -f "${off}" ]] && return 1
  [[ -f "${dst}" || -f "${vendor}" ]]
}

sync_isolation_conf() {
  is_trivalent || return 0
  if [[ -f "${ISO_OFF}" ]]; then
    as_root rm -f "${ISO_CONF}"
  else
    as_root mkdir -p "${TRIV_CONF_D}"
    as_root cp -a "${ISO_CONF_SRC}" "${ISO_CONF}"
  fi
}

trivalent_present() {
  [[ -e /usr/bin/trivalent ]] \
    || [[ -e /usr/lib64/trivalent/trivalent ]] \
    || [[ -e /usr/lib/trivalent/trivalent ]]
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
  if [[ -x /usr/libexec/unwoke/flatpak-record.sh ]]; then
    info "flatpak-record: $(/usr/libexec/unwoke/flatpak-record.sh status)"
  fi
  if [[ -x /usr/libexec/unwoke/network-fs.sh ]]; then
    info "network-fs: $(/usr/libexec/unwoke/network-fs.sh status)"
  fi
  if [[ -x /usr/libexec/unwoke/brew.sh ]]; then
    info "homebrew: $(/usr/libexec/unwoke/brew.sh status)"
  fi
  if [[ -x /usr/libexec/unwoke/camera-mic.sh ]]; then
    info "camera-mic: $(/usr/libexec/unwoke/camera-mic.sh status)"
  fi
  if [[ -x /usr/libexec/unwoke/admin-split.sh ]]; then
    info "admin-split: $(/usr/libexec/unwoke/admin-split.sh status)"
  fi
  if [[ -x /usr/libexec/unwoke/bluetooth.sh ]]; then
    info "bluetooth: $(/usr/libexec/unwoke/bluetooth.sh status)"
  fi
  if [[ -x /usr/libexec/unwoke/toolbox.sh ]]; then
    info "toolbox/distrobox: $(/usr/libexec/unwoke/toolbox.sh status)"
  fi
  if [[ -x /usr/libexec/unwoke/extra-daemons.sh ]]; then
    info "extra-daemons: $(/usr/libexec/unwoke/extra-daemons.sh status)"
  fi
  if [[ -x /usr/libexec/unwoke/privacy.sh ]]; then
    /usr/libexec/unwoke/privacy.sh status
  fi
  if [[ -x /usr/libexec/unwoke/ramdisk.sh ]]; then
    info "ramdisk-exec: $(/usr/libexec/unwoke/ramdisk.sh status)"
  fi
  if [[ -x /usr/libexec/unwoke/cet.sh ]]; then
    info "cet: $(/usr/libexec/unwoke/cet.sh status)"
  fi
  if [[ -x /usr/libexec/unwoke/boot-perm.sh ]]; then
    info "boot-perm: $(/usr/libexec/unwoke/boot-perm.sh status)"
  fi
  if [[ -x /usr/libexec/unwoke/ca-trim.sh ]]; then
    info "extra-cas: $(/usr/libexec/unwoke/ca-trim.sh status)"
  fi
  if [[ -x /usr/libexec/unwoke/stock-nags.sh ]]; then
    info "stock-nags: $(/usr/libexec/unwoke/stock-nags.sh status)"
  fi
  if [[ -x /usr/libexec/unwoke/nts.sh ]]; then
    info "nts: $(/usr/libexec/unwoke/nts.sh status)"
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
    if trivalent_present; then
      bad "Trivalent present on a browserless image"
    else
      ok "no Trivalent"
    fi
    if [[ -e /opt/brave.com/brave/brave ]]; then
      bad "full brave-browser is installed"
    else
      ok "no full brave-browser"
    fi
    info "browser policies: n/a"
    if [[ -f /etc/unwoke/allow-browsers ]]; then
      bad "allow-browsers ON — easy host browser installs are unlocked"
    else
      ok "allow-browsers OFF — ujust set-allow-browsers on ALLOW to unlock"
    fi
  elif is_trivalent; then
    ok "flavor: trivalent (stock Trivalent + Unwoke policy packs)"
    if command -v semodule >/dev/null && semodule -l 2>/dev/null | grep -qx unwoke_brave; then
      bad "unwoke_brave loaded — trivalent flavor must not add brave_t"
    else
      ok "no brave_t (stock trivalent_t stays)"
    fi
    if command -v semodule >/dev/null && semodule -l 2>/dev/null | grep -Eqx 'trivalent|trivalent-selinux'; then
      ok "Trivalent SELinux module listed"
    else
      info "Trivalent SELinux module name not listed (package still provides the jail)"
    fi
    if trivalent_present; then
      ok "Trivalent binary present"
    else
      bad "Trivalent binary missing"
    fi
    if [[ -e /opt/brave.com/brave-origin/brave ]]; then
      bad "Brave Origin ELF present on a trivalent image"
    else
      ok "no Brave Origin"
    fi
    if [[ -e /opt/brave.com/brave/brave ]]; then
      bad "full brave-browser is also installed"
    fi
    echo "  -- Trivalent policy packs (restart Trivalent after changes) --"
    status_packs
    if conf_is_on "${NET_CONF}" "${NET_OFF}" /usr/etc/trivalent/trivalent.conf.d/50-unwoke-network-sandbox.conf; then
      ok "Network Service Sandbox forced on (may clear cookies) — ujust set-trivalent-network-sandbox off"
    else
      info "Network Service Sandbox not forced — ujust set-trivalent-network-sandbox on"
    fi
    if conf_is_on "${REF_CONF}" "${REF_OFF}" /usr/etc/trivalent/trivalent.conf.d/60-unwoke-referrers.conf; then
      ok "Punycode + clear-cross-origin-referrers flags on — ujust set-trivalent-referrers off"
    else
      info "Punycode / referrer flags off — ujust set-trivalent-referrers on"
    fi
    info "Bubblejail: n/a (do not wrap Trivalent; stock already jails it)"
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
    echo "  -- Brave Origin policy packs (restart the browser after changes) --"
    status_packs
    if [[ -f "${BUBBLE_OFF}" ]]; then
      info "Brave Bubblejail off — ujust set-brave-bubblejail on"
    else
      ok "Brave Bubblejail on (default). GPU may break — ujust set-brave-bubblejail off"
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
  echo "  ujust set-flatpak-record on|off"
  echo "  ujust set-network-fs on|off"
  echo "  ujust set-ramdisk-exec on|off"
  echo "  ujust set-cet on|off"
  echo "  ujust set-boot-perm on|off"
  echo "  ujust set-extra-cas on|off"
  echo "  ujust set-brew on|off"
  echo "  ujust set-camera-mic on|off"
  echo "  ujust set-admin-split on|off|add NAME"
  echo "  ujust set-bluetooth on|off"
  echo "  ujust set-toolbox on|off"
  echo "  ujust set-extra-daemons on|off"
  echo "  ujust set-countme on|off"
  echo "  ujust set-connectivity-check on|off"
  echo "  ujust set-dhcp-hostname on|off"
  echo "  ujust set-thumbnails on|off"
  echo "  ujust set-stock-nags on|off"
  if is_browserless; then
    echo "  ujust set-allow-browsers on ALLOW|off"
  else
    echo "  ujust set-brave-hardening on|off     (also set-trivalent-hardening)"
    echo "  ujust set-brave-devices on|off"
    echo "  ujust set-brave-jitless on|off"
    echo "  ujust set-brave-extensions block|allow"
    echo "  ujust set-brave-isolation on|off"
    echo "  ujust set-brave-sandbox on|off"
    echo "  ujust set-brave-devtools lock|allow  (default lock)"
    if is_origin; then
      echo "  ujust set-brave-bubblejail on|off"
    fi
    if is_trivalent; then
      echo "  ujust set-trivalent-network-sandbox on|off"
      echo "  ujust set-trivalent-referrers on|off"
    fi
  fi
  echo "Stock: ujust set-unconfined-userns  ujust set-kargs-hardening  ujust audit-secureblue"
}

status_packs() {
  local b
  b="$(browser_name)"
  if policy_is_on "${HARDEN_FILE}" "${HARDEN_OFF}"; then
    ok "${b} hardening pack on (HTTPS/metrics/autofill/passwords)"
  else
    info "${b} hardening pack off — ujust set-brave-hardening on"
  fi
  if policy_is_on "${DEVICES_FILE}" "${DEVICES_OFF}"; then
    ok "${b} device pack on (USB/BT/serial/camera/mic/geo blocked)"
  else
    info "${b} device pack off — ujust set-brave-devices on"
  fi
  if policy_is_on "${JITLESS_FILE}" "${JITLESS_OFF}"; then
    ok "${b} JIT blocked (some sites break) — ujust set-brave-jitless off"
  else
    info "${b} JIT allowed — ujust set-brave-jitless on"
  fi
  if policy_is_on "${EXT_FILE}" "${EXT_OFF}"; then
    ok "${b} extension installs blocked — ujust set-brave-extensions allow"
  else
    info "${b} extension installs allowed — ujust set-brave-extensions block"
  fi
  if policy_is_on "${ISO_FILE}" "${ISO_OFF}"; then
    ok "${b} isolation pack on (no WebGL/WebGPU, SitePerProcess) — ujust set-brave-isolation off"
  else
    info "${b} isolation pack off — ujust set-brave-isolation on"
  fi
  if policy_is_on "${SANDBOX_FILE}" "${SANDBOX_OFF}"; then
    ok "${b} extra sandbox pack on (audio sandbox, no screen capture, no JS optimizer) — ujust set-brave-sandbox off"
  else
    info "${b} extra sandbox pack off — ujust set-brave-sandbox on"
  fi
  if policy_is_on "${DEVTOOLS_FILE}" "${DEVTOOLS_OFF}"; then
    ok "${b} DevTools locked (default) — ujust set-brave-devtools allow"
  else
    info "${b} DevTools allowed — ujust set-brave-devtools lock"
  fi
}

cmd_audit() {
  cmd_status
  fail=0
  command -v semodule >/dev/null && semodule -l 2>/dev/null | grep -qx harden_userns || fail=1
  if is_browserless; then
    [[ ! -e /opt/brave.com/brave-origin/brave ]] || fail=1
    [[ ! -e /opt/brave.com/brave/brave ]] || fail=1
    trivalent_present && fail=1
    if command -v semodule >/dev/null && semodule -l 2>/dev/null | grep -qx unwoke_brave; then
      fail=1
    fi
  elif is_trivalent; then
    trivalent_present || fail=1
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
  # Stock #887: warn if Flatpak session/system bus is allowed (not merely negated).
  if command -v flatpak >/dev/null; then
    local ov tok
    ov="$(flatpak override --show 2>/dev/null || true)"
    ov="${ov}"$'\n'"$(flatpak override --user --show 2>/dev/null || true)"
    tok="$(printf '%s\n' "${ov}" | tr ';,' '\n' | sed 's/.*=//')"
    if grep -qx 'session-bus' <<<"${tok}"; then
      info "Flatpak session-bus is allowed (stock audit does not warn yet)"
    fi
    if grep -qx 'system-bus' <<<"${tok}"; then
      info "Flatpak system-bus is allowed (stock audit does not warn yet)"
    fi
    if grep -q 'org.freedesktop.Flatpak' <<<"${ov}" && ! grep -q '!org.freedesktop.Flatpak' <<<"${ov}"; then
      info "Flatpak talk-name org.freedesktop.Flatpak is present (dangerous bus)"
    fi
  fi
  if [[ ! -f /usr/share/unwoke/SHIPPED-FIRST.txt ]] || ! grep -q 'UNWOKE-SHIPPED-FIRST' /usr/share/unwoke/SHIPPED-FIRST.txt; then
    bad "public mark /usr/share/unwoke/SHIPPED-FIRST.txt"
    fail=1
  else
    ok "public mark UNWOKE-SHIPPED-FIRST"
  fi
  if [[ ! -f /usr/share/unwoke/NOTICE ]] || [[ ! -f /usr/share/unwoke/LICENSE ]]; then
    bad "missing /usr/share/unwoke/NOTICE or LICENSE"
    fail=1
  fi
  # Stock #2508: warn (or fail on browserless) if a Flatpak web browser is installed.
  if command -v flatpak >/dev/null; then
    local apps br
    apps="$(flatpak list --app --columns=application 2>/dev/null || true)"
    if [[ -n "${apps}" ]]; then
      while IFS= read -r br; do
        [[ -n "${br}" ]] || continue
        case "${br}" in
          org.mozilla.firefox*|com.google.Chrome*|com.brave.Browser*|com.microsoft.Edge*|org.chromium.Chromium*|io.github.ungoogled*|net.mullvad.MullvadBrowser*|org.torproject.*|io.gitlab.librewolf*|app.zen_browser.*|org.gnome.Epiphany*|com.vivaldi.*|com.opera.Opera*)
            info "Flatpak web browser installed: ${br} (stock audit does not warn yet)"
            if is_browserless; then
              bad "browserless image with a Flatpak browser"
              fail=1
            fi
            ;;
        esac
      done <<<"${apps}"
    fi
  fi
  exit "${fail}"
}

cmd_pack() {
  need_browser_policies
  local name="$1" src="$2" file="$3" off="$4" action="${5:-status}"
  case "${action}" in
    on|enable|block|lock)
      policy_on "${src}" "${file}" "${off}"
      if [[ "${file}" == "${ISO_FILE}" ]]; then
        as_root mkdir -p /etc/unwoke
        as_root rm -f "${ISO_OFF}"
        sync_isolation_conf
      fi
      echo "${name} ON. Restart $(browser_name)."
      ;;
    off|disable|allow)
      policy_off "${file}" "${off}"
      if [[ "${file}" == "${ISO_FILE}" ]]; then
        sync_isolation_conf
      fi
      echo "${name} OFF. Restart $(browser_name)."
      if [[ "${file}" == "${HARDEN_FILE}" ]]; then
        echo "WARN: that pack is HTTPS-only, no metrics, no ping, no Privacy Sandbox, no Cast. This is a security/privacy loosen. Put it back: ujust set-brave-hardening on"
      fi
      if [[ "${file}" == "${JITLESS_FILE}" || "${file}" == "${ISO_FILE}" || "${file}" == "${DEVICES_FILE}" ]]; then
        echo "WARN: that pack is a security default. Turning it off also makes this browser look closer to stock Trivalent (smaller uniqueness). Tutorial: fingerprint"
      fi
      ;;
    status)
      policy_status "${file}" "${off}"
      ;;
    *)
      echo "usage: on|off|status" >&2
      exit 2
      ;;
  esac
}

cmd_conf() {
  need_trivalent
  local name="$1" src="$2" dst="$3" off="$4" action="${5:-status}" vendor="$6"
  case "${action}" in
    on|enable)
      conf_on "${src}" "${dst}" "${off}"
      echo "${name} ON. Restart Trivalent."
      ;;
    off|disable)
      conf_off "${dst}" "${off}"
      echo "${name} OFF. Restart Trivalent."
      ;;
    status)
      conf_status "${dst}" "${off}" "${vendor}"
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
    echo "This toggle is for -browserless images. Origin already ships Brave Origin; -trivalent already ships Trivalent." >&2
    exit 1
  fi
  local action="${1:-status}"
  case "${action}" in
    on|enable)
      confirm_allow "${2:-}"
      as_root /usr/libexec/unwoke/browser-guard.sh lift
      /usr/libexec/unwoke/browser-guard.sh unmask-user || true
      echo "Host browser installs unlocked."
      echo "Flathub stays as you set it (default off). Flatpak browsers: ujust set-flathub verified"
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

ensure_bubble_instance() {
  command -v bubblejail >/dev/null || return 0
  bubblejail list 2>/dev/null | grep -qx brave-origin && return 0
  bubblejail create --profile chromium brave-origin \
    || bubblejail create --desktop-entry /usr/share/applications/brave-origin.desktop brave-origin \
    || bubblejail create brave-origin \
    || true
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
      as_root mkdir -p /etc/unwoke
      as_root rm -f "${BUBBLE_OFF}"
      ensure_bubble_instance
      echo "Bubblejail ON (default). GPU/PipeWire/portals may break."
      echo "Revert: ujust set-brave-bubblejail off. Restart Brave Origin."
      ;;
    off|disable)
      as_root mkdir -p /etc/unwoke
      as_root touch "${BUBBLE_OFF}"
      echo "Bubblejail OFF. Launcher runs /opt/brave.com/brave-origin/brave directly."
      ;;
    status)
      if [[ -f "${BUBBLE_OFF}" ]]; then
        echo "off (${BUBBLE_OFF})"
      else
        echo "on (default)"
      fi
      ;;
    *)
      echo "usage: ujust set-brave-bubblejail on|off|status" >&2
      exit 2
      ;;
  esac
}

boot_pack() {
  local src="$1" file="$2" off="$3" d
  if [[ -f "${off}" ]]; then
    while IFS= read -r d; do
      [[ -n "${d}" ]] || continue
      rm -f "${d}/${file}"
    done < <(policy_dirs)
    return 0
  fi
  [[ -f "${src}" ]] || return 0
  while IFS= read -r d; do
    [[ -n "${d}" ]] || continue
    mkdir -p "${d}"
    cp -a "${src}" "${d}/${file}" || true
  done < <(policy_dirs)
}

boot_conf() {
  local src="$1" dst="$2" off="$3"
  if [[ -f "${off}" ]]; then
    rm -f "${dst}"
    return 0
  fi
  [[ -f "${src}" ]] || return 0
  mkdir -p "$(dirname "${dst}")"
  cp -a "${src}" "${dst}" || true
}

cmd_apply_boot() {
  [[ "$(id -u)" -eq 0 ]] || { echo "apply-boot needs root" >&2; exit 1; }
  mkdir -p /etc/unwoke
  if is_browserless; then
    echo "unwoke: browserless — no browser policies"
    if [[ ! -f /etc/unwoke/flathub ]]; then
      printf 'off\n' > /etc/unwoke/flathub
    fi
    if [[ -x /usr/libexec/unwoke/flathub.sh ]]; then
      /usr/libexec/unwoke/flathub.sh apply-boot || true
    fi
  else
    boot_pack "${HARDEN_SRC}" "${HARDEN_FILE}" "${HARDEN_OFF}"
    boot_pack "${DEVICES_SRC}" "${DEVICES_FILE}" "${DEVICES_OFF}"
    boot_pack "${JITLESS_SRC}" "${JITLESS_FILE}" "${JITLESS_OFF}"
    boot_pack "${EXT_SRC}" "${EXT_FILE}" "${EXT_OFF}"
    boot_pack "${ISO_SRC}" "${ISO_FILE}" "${ISO_OFF}"
    boot_pack "${SANDBOX_SRC}" "${SANDBOX_FILE}" "${SANDBOX_OFF}"
    boot_pack "${DEVTOOLS_SRC}" "${DEVTOOLS_FILE}" "${DEVTOOLS_OFF}"
    if is_trivalent; then
      mkdir -p "${TRIV_CONF_D}"
      boot_conf "${ISO_CONF_SRC}" "${ISO_CONF}" "${ISO_OFF}"
      boot_conf "${NET_SRC}" "${NET_CONF}" "${NET_OFF}"
      boot_conf "${REF_SRC}" "${REF_CONF}" "${REF_OFF}"
    fi
    if [[ ! -f /etc/unwoke/flathub ]]; then
      printf 'off\n' > /etc/unwoke/flathub
    fi
    if [[ -x /usr/libexec/unwoke/flathub.sh ]]; then
      /usr/libexec/unwoke/flathub.sh apply-boot || true
    fi
  fi
  if [[ -x /usr/libexec/unwoke/flatpak-lockdown.sh ]]; then
    /usr/libexec/unwoke/flatpak-lockdown.sh apply-boot || true
  fi
  if [[ -x /usr/libexec/unwoke/flatpak-record.sh ]]; then
    /usr/libexec/unwoke/flatpak-record.sh apply-boot || true
  fi
  if [[ -x /usr/libexec/unwoke/network-fs.sh ]]; then
    /usr/libexec/unwoke/network-fs.sh apply-boot || true
  fi
  if [[ -x /usr/libexec/unwoke/brew.sh ]]; then
    /usr/libexec/unwoke/brew.sh apply-boot || true
  fi
  if [[ -x /usr/libexec/unwoke/camera-mic.sh ]]; then
    /usr/libexec/unwoke/camera-mic.sh apply-boot || true
  fi
  if [[ -x /usr/libexec/unwoke/admin-split.sh ]]; then
    /usr/libexec/unwoke/admin-split.sh apply-boot || true
  fi
  if [[ -x /usr/libexec/unwoke/bluetooth.sh ]]; then
    /usr/libexec/unwoke/bluetooth.sh apply-boot || true
  fi
  if [[ -x /usr/libexec/unwoke/toolbox.sh ]]; then
    /usr/libexec/unwoke/toolbox.sh apply-boot || true
  fi
  if [[ -x /usr/libexec/unwoke/extra-daemons.sh ]]; then
    /usr/libexec/unwoke/extra-daemons.sh apply-boot || true
  fi
  if [[ -x /usr/libexec/unwoke/privacy.sh ]]; then
    /usr/libexec/unwoke/privacy.sh apply-boot || true
  fi
  if [[ -x /usr/libexec/unwoke/ramdisk.sh ]]; then
    /usr/libexec/unwoke/ramdisk.sh apply-boot || true
  fi
  if [[ -x /usr/libexec/unwoke/cet.sh ]]; then
    /usr/libexec/unwoke/cet.sh apply-boot || true
  fi
  if [[ -x /usr/libexec/unwoke/boot-perm.sh ]]; then
    /usr/libexec/unwoke/boot-perm.sh apply-boot || true
  fi
  if [[ -x /usr/libexec/unwoke/ca-trim.sh ]]; then
    /usr/libexec/unwoke/ca-trim.sh apply-boot || true
  fi
  if [[ -x /usr/libexec/unwoke/nts.sh ]]; then
    /usr/libexec/unwoke/nts.sh apply-boot || true
  fi
}

cmd_apply_user() {
  if [[ -x /usr/libexec/unwoke/flatpak-lockdown.sh ]]; then
    /usr/libexec/unwoke/flatpak-lockdown.sh apply-user || true
  fi
  if [[ -x /usr/libexec/unwoke/flatpak-record.sh ]]; then
    /usr/libexec/unwoke/flatpak-record.sh apply-user || true
  fi
  if [[ -x /usr/libexec/unwoke/theme.sh ]]; then
    /usr/libexec/unwoke/theme.sh apply-user-once || true
  fi
  if is_origin && [[ ! -f "${BUBBLE_OFF}" ]]; then
    ensure_bubble_instance || true
  fi
  if [[ -x /usr/libexec/unwoke/stock-nags.sh ]]; then
    /usr/libexec/unwoke/stock-nags.sh apply-user || true
  fi
}

usage() {
  echo "usage: toggles.sh ... brew|camera-mic|admin-split|bluetooth|toolbox|apply-boot|apply-user" >&2
  exit 2
}

main="${1:-status}"
shift || true
case "${main}" in
  status) cmd_status ;;
  audit) cmd_audit ;;
  hardening) cmd_pack "hardening pack" "${HARDEN_SRC}" "${HARDEN_FILE}" "${HARDEN_OFF}" "${1:-status}" ;;
  devices) cmd_pack "device pack" "${DEVICES_SRC}" "${DEVICES_FILE}" "${DEVICES_OFF}" "${1:-status}" ;;
  jitless) cmd_pack "JIT-less" "${JITLESS_SRC}" "${JITLESS_FILE}" "${JITLESS_OFF}" "${1:-status}" ;;
  extensions)
    case "${1:-status}" in
      block|on|enable) cmd_pack "extension block" "${EXT_SRC}" "${EXT_FILE}" "${EXT_OFF}" on ;;
      allow|off|disable) cmd_pack "extension block" "${EXT_SRC}" "${EXT_FILE}" "${EXT_OFF}" off ;;
      status) cmd_pack "extension block" "${EXT_SRC}" "${EXT_FILE}" "${EXT_OFF}" status ;;
      *) echo "usage: ujust set-brave-extensions block|allow|status" >&2; exit 2 ;;
    esac
    ;;
  isolation) cmd_pack "isolation pack" "${ISO_SRC}" "${ISO_FILE}" "${ISO_OFF}" "${1:-status}" ;;
  sandbox) cmd_pack "extra sandbox pack" "${SANDBOX_SRC}" "${SANDBOX_FILE}" "${SANDBOX_OFF}" "${1:-status}" ;;
  devtools)
    case "${1:-status}" in
      lock|on|enable|block) cmd_pack "DevTools lock" "${DEVTOOLS_SRC}" "${DEVTOOLS_FILE}" "${DEVTOOLS_OFF}" on ;;
      allow|off|disable) cmd_pack "DevTools lock" "${DEVTOOLS_SRC}" "${DEVTOOLS_FILE}" "${DEVTOOLS_OFF}" off ;;
      status) cmd_pack "DevTools lock" "${DEVTOOLS_SRC}" "${DEVTOOLS_FILE}" "${DEVTOOLS_OFF}" status ;;
      *) echo "usage: ujust set-brave-devtools lock|allow|status" >&2; exit 2 ;;
    esac
    ;;
  network-sandbox) cmd_conf "Network Service Sandbox" "${NET_SRC}" "${NET_CONF}" "${NET_OFF}" "${1:-status}" \
    /usr/etc/trivalent/trivalent.conf.d/50-unwoke-network-sandbox.conf ;;
  referrers) cmd_conf "Punycode + clear-cross-origin-referrers" "${REF_SRC}" "${REF_CONF}" "${REF_OFF}" "${1:-status}" \
    /usr/etc/trivalent/trivalent.conf.d/60-unwoke-referrers.conf ;;
  allow-browsers) cmd_allow_browsers "${1:-status}" "${2:-}" ;;
  flathub) exec /usr/libexec/unwoke/flathub.sh "${1:-status}" ;;
  lockdown) exec /usr/libexec/unwoke/flatpak-lockdown.sh "${1:-status}" ;;
  flatpak-record) exec /usr/libexec/unwoke/flatpak-record.sh "${1:-status}" ;;
  network-fs) exec /usr/libexec/unwoke/network-fs.sh "${1:-status}" ;;
  bubblejail) cmd_bubblejail "${1:-status}" ;;
  brew) exec /usr/libexec/unwoke/brew.sh "${1:-status}" ;;
  camera-mic) exec /usr/libexec/unwoke/camera-mic.sh "${1:-status}" ;;
  admin-split) exec /usr/libexec/unwoke/admin-split.sh "${1:-status}" "${2:-}" ;;
  bluetooth) exec /usr/libexec/unwoke/bluetooth.sh "${1:-status}" ;;
  toolbox) exec /usr/libexec/unwoke/toolbox.sh "${1:-status}" ;;
  extra-daemons) exec /usr/libexec/unwoke/extra-daemons.sh "${1:-status}" ;;
  ramdisk-exec) exec /usr/libexec/unwoke/ramdisk.sh "${1:-status}" ;;
  cet) exec /usr/libexec/unwoke/cet.sh "${1:-status}" ;;
  boot-perm) exec /usr/libexec/unwoke/boot-perm.sh "${1:-status}" ;;
  extra-cas) exec /usr/libexec/unwoke/ca-trim.sh "${1:-status}" ;;
  nts) exec /usr/libexec/unwoke/nts.sh "${1:-status}" ;;
  countme) exec /usr/libexec/unwoke/privacy.sh countme "${1:-status}" ;;
  connectivity|connectivity-check) exec /usr/libexec/unwoke/privacy.sh connectivity "${1:-status}" ;;
  dhcp-hostname) exec /usr/libexec/unwoke/privacy.sh dhcp-hostname "${1:-status}" ;;
  thumbnails) exec /usr/libexec/unwoke/privacy.sh thumbnails "${1:-status}" ;;
  stock-nags) exec /usr/libexec/unwoke/stock-nags.sh "${1:-status}" ;;
  apply-boot) cmd_apply_boot ;;
  apply-user) cmd_apply_user ;;
  *) usage ;;
esac
