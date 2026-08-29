#!/usr/bin/env bash
# Origin and browserless flavors: drop stock Trivalent. The -trivalent
# flavor does not run this, so Vanadium patches + trivalent_t stay.
set -oue pipefail

if command -v dnf5 >/dev/null; then
  dnf5 -y remove --skip-unavailable \
    trivalent trivalent-selinux trivalent-qt6-ui || true
elif command -v dnf >/dev/null; then
  dnf -y remove \
    trivalent trivalent-selinux trivalent-qt6-ui || true
fi
