#!/usr/bin/env bash
# Browserless flavor: no default browser, no brave_t. Stock harden_userns.
set -oue pipefail

mkdir -p /usr/share/unwoke
printf 'browserless\n' > /usr/share/unwoke/flavor

for f in \
  /usr/share/applications/mimeapps.list \
  /usr/etc/xdg/mimeapps.list \
  /etc/xdg/mimeapps.list
do
  [[ -f "$f" ]] || continue
  sed -i -E '/trivalent\.desktop|brave-origin\.desktop|brave-browser\.desktop/d' "$f"
done

for kg in \
  /usr/etc/xdg/kdeglobals \
  /etc/xdg/kdeglobals \
  /usr/share/kde-settings/kde-profile/default/share/config/kdeglobals
do
  [[ -f "$kg" ]] || continue
  sed -i '/^BrowserApplication=/d' "$kg"
done

for d in trivalent.desktop brave-origin.desktop brave-browser.desktop \
         io.github.kolunmi.Bazaar.desktop org.gnome.Software.desktop \
         org.kde.discover.desktop; do
  if [[ -f "/usr/share/applications/${d}" ]]; then
    grep -q '^Hidden=' "/usr/share/applications/${d}" || echo 'Hidden=true' >> "/usr/share/applications/${d}"
  fi
done

if command -v glib-compile-schemas >/dev/null && [[ -d /usr/share/glib-2.0/schemas ]]; then
  glib-compile-schemas /usr/share/glib-2.0/schemas || true
fi
