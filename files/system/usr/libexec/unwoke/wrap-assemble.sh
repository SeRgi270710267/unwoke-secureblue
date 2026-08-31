#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Stock distrobox-assemble / toolbox-assemble already ask container userns.
# Overlay extra: /usr/bin/toolbox and distrobox are wrappers until set-toolbox on.
set -euo pipefail

kind="${1:-distrobox}"
shift || true

ask() {
  local prompt="$1" def="${2:-N}"
  local ans=""
  read -r -p "${prompt} [${def}] " ans || true
  ans="${ans:-$def}"
  [[ "${ans}" == [yY] ]]
}

echo
echo "=== ${kind}-assemble (stock recipe intercepted) ==="
echo "Unwoke: toolbox/distrobox binaries are stubs until ujust set-toolbox on."
echo "Stock already asks container userns. We ask the overlay wrapper first."
echo

if [[ ! -f /etc/unwoke/allow-toolbox ]]; then
  if ! ask "Turn toolbox/distrobox wrappers on? Required for assemble to exec the real binary." "y"; then
    echo "Aborted. Later: ujust set-toolbox on && ujust ${kind}-assemble"
    exit 0
  fi
  bash /usr/libexec/unwoke/toggles.sh toolbox on || true
fi

stock="ujust ${kind}-assemble-stock"
if command -v ujust >/dev/null && ujust --summary 2>/dev/null | grep -qw "${kind}-assemble-stock"; then
  exec ujust "${kind}-assemble-stock" "$@"
fi
echo "Stock ${kind}-assemble-stock not on this image. Wrapper is on; run their command after rebase if it appears."
exit 0
