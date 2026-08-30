#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Origin and browserless flavors: drop stock Trivalent. The -trivalent
# flavor does not run this, so Vanadium patches + trivalent_t stay.
set -oue pipefail

# Files only. Do not `dnf remove`: Origin compose dnf+WAL left Packages
# malformed so live `rpm -q kernel-core` died (USB wrap 33311501669).
# Browserless USB was green with dnf, but files-only is enough for inspect
# (no Trivalent ELF) and keeps the ostree sqlite readable.

# ostree compose can leave the ELF/symlink. Delete the bits inspect looks
# for so Origin/browserless do not ship a house Trivalent.
rm -f /usr/bin/trivalent /usr/sbin/trivalent
rm -rf /usr/lib64/trivalent /usr/lib/trivalent
for d in trivalent.desktop org.secureblue.trivalent.desktop; do
  f="/usr/share/applications/${d}"
  if [[ -f "${f}" ]]; then
    grep -q '^Hidden=' "${f}" || echo 'Hidden=true' >> "${f}"
  fi
done
