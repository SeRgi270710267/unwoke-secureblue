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

BLOCK=/usr/share/unwoke/blocked-bin
mkdir -p "${BLOCK}"
if [[ -f "${BLOCK}/deny-toolbox.sh" ]]; then
  chmod a+x "${BLOCK}/deny-toolbox.sh"
  for n in toolbox distrobox distrobox-create distrobox-enter distrobox-list \
           distrobox-rm distrobox-stop distrobox-upgrade distrobox-ephemeral \
           distrobox-generate-entry distrobox-assemble distrobox-host-exec \
           distrobox-export distrobox-init distrobox-clone; do
    ln -sf deny-toolbox.sh "${BLOCK}/${n}"
  done
fi

if command -v systemctl >/dev/null; then
  systemctl enable unwoke-first-boot.service || true
  systemctl enable unwoke-browser-guard.service || true
  systemctl --global enable unwoke-browser-guard.service || true
  systemctl --global enable unwoke-user-defaults.service || true
fi

if command -v glib-compile-schemas >/dev/null && [[ -d /usr/share/glib-2.0/schemas ]]; then
  glib-compile-schemas /usr/share/glib-2.0/schemas || true
fi
