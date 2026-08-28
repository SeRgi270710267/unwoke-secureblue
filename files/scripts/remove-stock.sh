#!/usr/bin/env bash
# Remove Trivalent and Bazaar if they are still in the base image.
# skip-unavailable so a future secureblue drop of either does not fail the build.
set -oue pipefail

if command -v dnf5 >/dev/null; then
  dnf5 -y remove --skip-unavailable \
    trivalent trivalent-selinux bazaar krunner-bazaar || true
elif command -v dnf >/dev/null; then
  dnf -y remove \
    trivalent trivalent-selinux bazaar krunner-bazaar || true
fi
