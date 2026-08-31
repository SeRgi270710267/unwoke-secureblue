#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Guided Proton.me install (like stock ujust install-steam).
# Strictest path first. Nothing auto-unlocks. No Flathub, no store.
set -euo pipefail

VENDOR="/usr/libexec/unwoke/vendor.py"
MAIL_KEY="proton_mail"
PASS_KEY="proton_pass"

ask() {
  local prompt="$1" def="${2:-N}"
  local ans=""
  read -r -p "${prompt} [${def}] " ans || true
  ans="${ans:-$def}"
  [[ "${ans}" == [yY] ]]
}

open_url() {
  local url="$1"
  echo "Opening ${url}"
  if command -v xdg-open >/dev/null; then
    xdg-open "${url}" >/dev/null 2>&1 || echo "Open that URL in Trivalent (house browser)."
  else
    echo "Open in Trivalent: ${url}"
  fi
}

pick_rpm() {
  python3 "${VENDOR}" pick "$1"
}

install_official_rpm() {
  local name="$1" key="$2"
  echo
  echo "=== Desktop ${name} (official RPM) ==="
  echo "This is NOT the strictest path. Strictest: Trivalent at proton.me."
  echo "The desktop app is Electron-class. On this OS it may need:"
  echo "  ujust set-unconfined-userns on   (lets unconfined domains create userns)"
  echo "  and sometimes dropping hardened_malloc for that app if it will not start."
  echo "Flathub stays off. Unfiltered Flathub is not used. Lockdown stays on."
  echo
  if ! ask "Download official ${name} RPM and verify SHA512, then layer it?" "n"; then
    echo "Aborted. Use the web app in Trivalent."
    return 0
  fi
  if ! ask "Allow unconfined userns if the app will not start (stock toggle, default No)?" "n"; then
    echo "Keeping harden_userns as-is. If the app fails after reboot, run this wizard again or: ujust set-unconfined-userns on"
  else
    if command -v ujust >/dev/null; then
      ujust set-unconfined-userns on || echo "userns toggle failed; continue with hash+layer if you still want it"
    fi
  fi
  echo "Fetching official version.json via vendor.py (${key})"
  local ver url sha
  mapfile -t meta < <(pick_rpm "${key}")
  ver="${meta[0]:-}"
  url="${meta[1]:-}"
  sha="${meta[2]:-}"
  [[ -n "${url}" && -n "${sha}" ]] || { echo "FAIL: could not parse official version.json" >&2; return 1; }
  echo "Version ${ver}"
  echo "URL ${url}"
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' RETURN
  local rpm="${tmp}/${name}.rpm"
  curl -fsSL --tlsv1.2 -o "${rpm}" "${url}"
  echo "${sha}  ${rpm}" | sha512sum --check --strict
  echo "SHA512 OK."
  if ! ask "rpm-ostree install this file (reboot required)?" "n"; then
    echo "Aborted after verify. File not layered."
    return 0
  fi
  if command -v rpm-ostree >/dev/null; then
    if [[ "$(id -u)" -eq 0 ]]; then
      rpm-ostree install "${rpm}"
    else
      command -v run0 >/dev/null || { echo "need run0 (wheel)" >&2; return 1; }
      run0 rpm-ostree install "${rpm}"
    fi
    echo "Layered. Reboot: systemctl reboot"
    # shellcheck source=/usr/libexec/unwoke/continue-ostree.sh
    source /usr/libexec/unwoke/continue-ostree.sh
    unwoke_write_continue proton
    if ask "Reboot now?" "n"; then
      systemctl reboot
    fi
  else
    echo "rpm-ostree missing. Install skipped."
  fi
}

vpn_wireguard() {
  echo
  echo "=== Proton VPN — WireGuard (strictest native tunnel) ==="
  echo "No Proton GUI, no Flathub, no extra repo."
  echo "1. In Trivalent: https://account.protonvpn.com/downloads  (WireGuard config)"
  echo "2. GNOME/KDE Settings → Network → VPN → Import from file"
  echo "   or: nmcli connection import type wireguard file ~/Downloads/*.conf"
  echo "3. DNS: keep the VPN's resolver. Do not turn on Trivalent DoH."
  echo "   If you use a custom Unbound path: ujust dns-selector → system default"
  echo
  open_url "https://account.protonvpn.com/downloads"
  open_tutorial_vpn
}

open_tutorial_vpn() {
  if [[ -x /usr/libexec/unwoke/open-tutorial.sh ]]; then
    bash /usr/libexec/unwoke/open-tutorial.sh proton || true
  fi
}

vpn_gui() {
  echo
  echo "=== Proton VPN GUI (official Fedora repo) ==="
  echo "Weaker than WireGuard import: extra RPM origin on an Atomic box."
  echo "Flathub unverified com.protonvpn.www is NOT used."
  if ! ask "Call stock ujust install-vpn if it exists (you still confirm their prompts)?" "n"; then
    echo "Aborted. Use WireGuard import instead."
    return 0
  fi
  if command -v ujust >/dev/null && ujust --summary 2>/dev/null | grep -qw install-vpn; then
    ujust install-vpn || echo "stock install-vpn failed"
  else
    echo "No stock install-vpn on this image."
    echo "Official Fedora guide: https://protonvpn.com/support/official-linux-vpn-fedora"
    echo "Do not add that repo unless you accept a third-party RPM origin."
  fi
}

open_web() {
  echo
  echo "=== Proton in Trivalent (recommended, no extra software) ==="
  echo "House browser. No Flathub, no Electron, no Xwayland, lockdown unchanged."
  open_url "https://mail.proton.me"
  open_url "https://pass.proton.me"
  open_url "https://calendar.proton.me"
  open_url "https://drive.proton.me"
  echo "Also: https://docs.proton.me  https://meet.proton.me  https://lumo.proton.me  https://wallet.proton.me"
}

menu() {
  cat <<'EOF'

Proton.me — Unwoke (strictest first)
No store. No unverified Flathub. Locks stay unless you say yes.

  1) Open Mail / Pass / Calendar / Drive in Trivalent (recommended)
  2) VPN: WireGuard import (strictest native)
  3) Desktop Mail — official RPM + SHA512 (asks userns)
  4) Desktop Pass — official RPM + SHA512 (asks userns)
  5) Desktop VPN GUI — stock helper if present (last)
  t) Tutorial
  q) Quit
EOF
}

jump="${1:-}"
case "${jump}" in
  --web|web) open_web; exit 0 ;;
  --vpn|vpn) vpn_wireguard; exit 0 ;;
  --mail-rpm) install_official_rpm mail "${MAIL_KEY}"; exit 0 ;;
  --pass-rpm) install_official_rpm pass "${PASS_KEY}"; exit 0 ;;
  --vpn-gui) vpn_gui; exit 0 ;;
  ""|--menu) ;;
  *) echo "usage: install-proton.sh [--web|--vpn|--mail-rpm|--pass-rpm|--vpn-gui]" >&2; exit 2 ;;
esac

echo "Unwoke Proton setup"
echo "Recommended image: *-trivalent. Web first. Desktop RPM is a named downgrade."
while true; do
  menu
  echo
  read -r -p "Choice: " ans || exit 0
  case "${ans}" in
    1) open_web ;;
    2) vpn_wireguard ;;
    3) install_official_rpm mail "${MAIL_KEY}" ;;
    4) install_official_rpm pass "${PASS_KEY}" ;;
    5) vpn_gui ;;
    t|T) bash /usr/libexec/unwoke/open-tutorial.sh proton || true ;;
    q|Q|"") exit 0 ;;
    *) echo "Unknown choice." ;;
  esac
done
