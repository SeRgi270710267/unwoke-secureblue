#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Guided IVPN (ivpn.net) install. Strictest path first. No store, no Snap.
set -euo pipefail

VENDOR="/usr/libexec/unwoke/vendor.py"
REPO_URL="$(python3 "${VENDOR}" url ivpn_repo 2>/dev/null || echo "https://repo.ivpn.net/stable/fedora/generic/ivpn.repo")"
ACCOUNT_URL="$(python3 "${VENDOR}" url ivpn_account 2>/dev/null || echo "https://www.ivpn.net/account/")"
WG_HELP="https://www.ivpn.net/setup/linux-wireguard"
SILVERBLUE="https://www.ivpn.net/knowledgebase/linux/fedora-silverblue/"

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
    xdg-open "${url}" >/dev/null 2>&1 || echo "Open in Trivalent: ${url}"
  else
    echo "Open in Trivalent: ${url}"
  fi
}

ostree_install() {
  local pkg="$1"
  if [[ "$(id -u)" -eq 0 ]]; then
    rpm-ostree install "${pkg}"
  else
    command -v run0 >/dev/null || { echo "need run0 (wheel)" >&2; return 1; }
    run0 rpm-ostree install "${pkg}"
  fi
}

write_repo() {
  local tmp
  tmp="$(mktemp)"
  curl -fsSL --tlsv1.2 -o "${tmp}" "${REPO_URL}"
  echo "Repo file (HTTPS). Check gpgcheck is 1:"
  cat "${tmp}"
  echo
  if ! grep -q '^gpgcheck=1' "${tmp}" && ! grep -q 'gpgcheck=1' "${tmp}"; then
    echo "WARN: gpgcheck not clearly 1. Abort unless you accept that."
    if ! ask "Write this repo anyway?" "n"; then
      rm -f "${tmp}"
      return 1
    fi
  fi
  if [[ "$(id -u)" -eq 0 ]]; then
    cp "${tmp}" /etc/yum.repos.d/ivpn.repo
    rpm-ostree refresh-md || true
  else
    run0 cp "${tmp}" /etc/yum.repos.d/ivpn.repo
    run0 rpm-ostree refresh-md || true
  fi
  rm -f "${tmp}"
}

wireguard() {
  echo
  echo "=== IVPN WireGuard (strictest native tunnel) ==="
  echo "No IVPN daemon, no extra RPM repo, no Snap, no Flathub."
  echo "AntiTracker lives in their official app — not in a raw WireGuard file"
  echo "unless you set IVPN DNS in the config they give you."
  echo
  echo "1. Sign in: ${ACCOUNT_URL}"
  echo "2. VPN Accounts → WireGuard → add a key / download a .conf"
  echo "3. Rename the file to 15 characters or less if GNOME says Cannot Import VPN"
  echo "4. Settings → Network → VPN → Import from file"
  echo "   or: nmcli connection import type wireguard file /path/to/short.conf"
  echo "5. DNS: keep the VPN resolver. Do not turn on Trivalent DoH."
  echo "   ujust dns-selector → system default if you customized Unbound"
  echo
  open_url "${ACCOUNT_URL}"
  echo "Manual WireGuard steps: ${WG_HELP}"
}

official_cli() {
  echo
  echo "=== Official IVPN CLI (their Fedora repo, Silverblue path) ==="
  echo "Extra RPM origin on an Atomic box. Stricter than Snap; weaker than WireGuard import."
  echo "They document: ${SILVERBLUE}"
  echo "Flathub stays off. Firewalld stays on (do not switch to UFW)."
  if ! ask "Add https://repo.ivpn.net Fedora repo and layer package 'ivpn'?" "n"; then
    echo "Aborted. Use WireGuard import."
    return 0
  fi
  write_repo
  ostree_install ivpn
  echo "Layered ivpn. After reboot: run0 systemctl enable --now ivpn-service"
  echo "Login: ivpn login   Connect: ivpn connect"
  if ask "Also layer ivpn-ui (GUI: AntiTracker, multi-hop)?" "n"; then
    ostree_install ivpn-ui
  fi
  if ask "Reboot now?" "n"; then
    systemctl reboot
  fi
}

stock_helper() {
  echo
  echo "=== Stock ujust install-vpn ==="
  echo "Their wizard may offer IVPN among providers. You still confirm their prompts."
  if ! ask "Run ujust install-vpn if it exists?" "n"; then
    return 0
  fi
  if command -v ujust >/dev/null && ujust --summary 2>/dev/null | grep -qw install-vpn; then
    ujust install-vpn || echo "stock install-vpn failed"
  else
    echo "No install-vpn on this image. Use WireGuard or official repo options."
  fi
}

menu() {
  cat <<'EOF'

IVPN (ivpn.net) — Unwoke
VPN + AntiTracker in their official app. Not a mail/pass suite.
No store. No Snap. Locks stay unless you say yes.

  1) WireGuard import (recommended, no extra software)
  2) Open account / WireGuard key page in Trivalent
  3) Official CLI (+ optional UI) via their signed Fedora repo
  4) Stock ujust install-vpn if present
  t) Tutorial
  q) Quit
EOF
}

jump="${1:-}"
case "${jump}" in
  --wg|wg) wireguard; exit 0 ;;
  --account) open_url "${ACCOUNT_URL}"; exit 0 ;;
  --repo|cli) official_cli; exit 0 ;;
  --stock) stock_helper; exit 0 ;;
  ""|--menu) ;;
  *) echo "usage: install-ivpn.sh [--wg|--account|--repo|--stock]" >&2; exit 2 ;;
esac

echo "Unwoke IVPN setup"
echo "Strictest: NetworkManager WireGuard. Official app only if you need AntiTracker/multi-hop in their GUI."
while true; do
  menu
  echo
  read -r -p "Choice: " ans || exit 0
  case "${ans}" in
    1) wireguard ;;
    2) open_url "${ACCOUNT_URL}" ;;
    3) official_cli ;;
    4) stock_helper ;;
    t|T) bash /usr/libexec/unwoke/open-tutorial.sh ivpn || true ;;
    q|Q|"") exit 0 ;;
    *) echo "Unknown choice." ;;
  esac
done
