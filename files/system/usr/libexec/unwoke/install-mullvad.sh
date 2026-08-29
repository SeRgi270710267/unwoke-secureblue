#!/usr/bin/env bash
# Guided Mullvad VPN. Strictest: WireGuard import. No store, no Snap.
set -euo pipefail
VENDOR="/usr/libexec/unwoke/vendor.py"
REPO_URL="$(python3 "${VENDOR}" url mullvad_repo 2>/dev/null || echo "https://repository.mullvad.net/rpm/stable/mullvad.repo")"
ACCOUNT_URL="$(python3 "${VENDOR}" url mullvad_account 2>/dev/null || echo "https://mullvad.net/en/account/wireguard-config")"
DOCS="https://mullvad.net/en/download/vpn/linux"

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
    run0 rpm-ostree install "${pkg}"
  fi
}

wireguard() {
  echo
  echo "=== Mullvad WireGuard (strictest native tunnel) ==="
  echo "No Mullvad daemon, no extra RPM repo, no Snap."
  echo "1. Sign in (account number, no email required): ${ACCOUNT_URL}"
  echo "2. Generate/download WireGuard .conf files"
  echo "3. GNOME: filename ≤ 15 characters or import fails"
  echo "4. Settings → Network → VPN → Import"
  echo "   or: nmcli connection import type wireguard file /path/to/short.conf"
  echo "5. DNS: keep Mullvad's resolver. Do not turn on Trivalent DoH."
  echo
  open_url "${ACCOUNT_URL}"
}

official_app() {
  echo
  echo "=== Official Mullvad VPN app (their Fedora repo) ==="
  echo "Extra RPM origin. Weaker than WireGuard import; needed for their GUI/kill switch."
  echo "Docs: ${DOCS}"
  echo "gpgcheck must stay 1. Firewalld stays on."
  if ! ask "Add https://repository.mullvad.net repo and layer mullvad-vpn?" "n"; then
    echo "Aborted. Use WireGuard import."
    return 0
  fi
  bash /usr/libexec/unwoke/install-vendor.sh mullvad_repo
}

stock_helper() {
  echo
  echo "=== Stock ujust install-vpn ==="
  echo "Their wizard may offer Mullvad. You still confirm their prompts."
  if ! ask "Run ujust install-vpn if it exists?" "n"; then
    return 0
  fi
  if command -v ujust >/dev/null && ujust --summary 2>/dev/null | grep -qw install-vpn; then
    ujust install-vpn || echo "stock install-vpn failed"
  else
    echo "No install-vpn on this image."
  fi
}

menu() {
  cat <<'EOF'

Mullvad VPN — Unwoke
VPN only (not Mullvad Browser). No store. No Snap.

  1) WireGuard import (recommended)
  2) Open WireGuard config page in Trivalent
  3) Official app via their signed Fedora repo
  4) Stock ujust install-vpn if present
  t) Tutorial
  q) Quit
EOF
}

jump="${1:-}"
case "${jump}" in
  --wg|wg) wireguard; exit 0 ;;
  --account) open_url "${ACCOUNT_URL}"; exit 0 ;;
  --repo) official_app; exit 0 ;;
  --stock) stock_helper; exit 0 ;;
  ""|--menu) ;;
  *) echo "usage: install-mullvad.sh [--wg|--account|--repo|--stock]" >&2; exit 2 ;;
esac

echo "Unwoke Mullvad setup"
echo "Strictest: NetworkManager WireGuard. Official app only if you need their GUI."
while true; do
  menu
  echo
  read -r -p "Choice: " ans || exit 0
  case "${ans}" in
    1) wireguard ;;
    2) open_url "${ACCOUNT_URL}" ;;
    3) official_app ;;
    4) stock_helper ;;
    t|T) bash /usr/libexec/unwoke/open-tutorial.sh mullvad || true ;;
    q|Q|"") exit 0 ;;
    *) echo "Unknown choice." ;;
  esac
done
