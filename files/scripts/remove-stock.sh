#!/usr/bin/env bash
# Strip Bazaar and GUI software stores. Browser packages stay unless a
# flavor script (remove-trivalent.sh) drops them.
# skip-unavailable so a future secureblue drop of either does not fail the build.
set -oue pipefail

if command -v dnf5 >/dev/null; then
  dnf5 -y remove --skip-unavailable \
    bazaar krunner-bazaar \
    gnome-software plasma-discover brave-browser || true
elif command -v dnf >/dev/null; then
  dnf -y remove \
    bazaar krunner-bazaar \
    gnome-software plasma-discover brave-browser || true
fi
