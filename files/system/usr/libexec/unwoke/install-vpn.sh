#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Stock ujust install-vpn layers IVPN/Mullvad/Proton/Tailscale and may
# switch DNS off Unbound. We do not call that script. WireGuard first.
set -euo pipefail

ask() {
  local prompt="$1" def="${2:-N}"
  local ans=""
  read -r -p "${prompt} [${def}] " ans || true
  ans="${ans:-$def}"
  [[ "${ans}" == [yY] ]]
}

echo
echo "=== VPN (stock ujust install-vpn is intercepted) ==="
echo "Stock layers a GUI RPM, may disable Unbound, and may ask unconfined userns."
echo "Unwoke: WireGuard import first. Official repo only if you insist."
echo "Nothing silent. Tailscale is the one stock provider we did not already wrap."
echo
cat <<'EOF'
  1) Proton VPN — WireGuard / official (ujust install-proton)
  2) IVPN — WireGuard / official (ujust install-ivpn)
  3) Mullvad — WireGuard / official (ujust install-mullvad)
  4) Tailscale — extra RPM origin (asked)
  q) Abort
EOF
echo
read -r -p "Choice [q]: " ans || exit 0
case "${ans}" in
  1) exec bash /usr/libexec/unwoke/install-proton.sh --vpn ;;
  2) exec bash /usr/libexec/unwoke/install-ivpn.sh ;;
  3) exec bash /usr/libexec/unwoke/install-mullvad.sh ;;
  4)
    echo
    echo "=== Tailscale (official Fedora repo) ==="
    echo "Stock install-vpn does this too. Extra origin on an Atomic box."
    echo "WireGuard users should pick 1–3 instead."
    echo "DNS: some Tailscale setups fight Unbound. Stock would switch to systemd-resolved."
    if ! ask "Add Tailscale repo (gpgcheck=1) and layer tailscale?" "n"; then
      echo "Aborted."
      exit 0
    fi
    if ask "Switch DNS resolver to systemd-resolved (stock does this; default No)?" "n"; then
      ujust dns-selector resolver resolved || echo "dns-selector failed; run it later"
    fi
    exec bash /usr/libexec/unwoke/install-vendor.sh tailscale_repo
    ;;
  *)
    echo "Aborted. Per-provider: ujust install-proton / install-ivpn / install-mullvad"
    exit 0
    ;;
esac
