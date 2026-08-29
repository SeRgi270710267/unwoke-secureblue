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

# ostree compose can leave the ELF/symlink after dnf remove. Delete the bits
# inspect looks for so Origin/browserless do not ship a house Trivalent.
rm -f /usr/bin/trivalent /usr/sbin/trivalent
rm -rf /usr/lib64/trivalent /usr/lib/trivalent
for d in trivalent.desktop org.secureblue.trivalent.desktop; do
  f="/usr/share/applications/${d}"
  if [[ -f "${f}" ]]; then
    grep -q '^Hidden=' "${f}" || echo 'Hidden=true' >> "${f}"
  fi
done
