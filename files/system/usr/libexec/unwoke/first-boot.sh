#!/usr/bin/env bash
# Enable unconfined user namespaces so official Brave can use its sandbox,
# and add unfiltered Flathub now that Bazaar is gone.
set -euo pipefail

if command -v semodule >/dev/null; then
  if semodule -l 2>/dev/null | grep -qx 'harden_userns'; then
    semodule --disable=harden_userns || true
  fi
fi

if command -v flatpak >/dev/null; then
  flatpak remote-add --if-not-exists --system flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
fi
