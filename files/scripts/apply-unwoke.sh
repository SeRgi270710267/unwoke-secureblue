#!/usr/bin/env bash
# Shared build-time overlay: hide leftover Trivalent/Bazaar/store/full-Brave
# launchers. Does not install a browser and does not touch harden_userns.
set -oue pipefail

for d in trivalent.desktop io.github.kolunmi.Bazaar.desktop \
         org.gnome.Software.desktop org.kde.discover.desktop \
         brave-browser.desktop; do
  if [[ -f "/usr/share/applications/${d}" ]]; then
    grep -q '^Hidden=' "/usr/share/applications/${d}" || echo 'Hidden=true' >> "/usr/share/applications/${d}"
  fi
done

rm -rf /usr/share/bazaar || true

if command -v systemctl >/dev/null; then
  systemctl enable unwoke-first-boot.service || true
  systemctl enable unwoke-browser-guard.service || true
  systemctl --global enable unwoke-browser-guard.service || true
fi

if command -v glib-compile-schemas >/dev/null && [[ -d /usr/share/glib-2.0/schemas ]]; then
  glib-compile-schemas /usr/share/glib-2.0/schemas || true
fi
