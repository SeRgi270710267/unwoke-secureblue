#!/usr/bin/env bash
# Runs at image build time. Makes Brave Origin the default browser, hides leftover
# Trivalent/Bazaar/store/full-Brave launchers. Does not touch harden_userns.
set -oue pipefail

swap_desktop() {
  local search="$1"
  local replace="$2"
  local f escaped
  escaped="$(printf '%s' "$search" | sed 's/[.[\*^$]/\\&/g')"
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    sed -i "s/${escaped}/${replace}/g" "$f"
  done < <(grep -rlF "$search" /usr /etc 2>/dev/null || true)
}

ORIGIN_DESKTOP="brave-origin.desktop"
if [[ ! -f "/usr/share/applications/${ORIGIN_DESKTOP}" ]]; then
  for d in /usr/share/applications/brave-origin*.desktop /usr/share/applications/com.brave.Origin*.desktop; do
    [[ -f "$d" ]] || continue
    ORIGIN_DESKTOP="$(basename "$d")"
    break
  done
fi

swap_desktop "trivalent.desktop" "${ORIGIN_DESKTOP}"
swap_desktop "brave-browser.desktop" "${ORIGIN_DESKTOP}"
swap_desktop "org.mozilla.firefox.desktop" "${ORIGIN_DESKTOP}"

mkdir -p /usr/share/applications /usr/etc/xdg
cat > /usr/share/applications/mimeapps.list <<EOF
[Default Applications]
text/html=${ORIGIN_DESKTOP}
application/xhtml+xml=${ORIGIN_DESKTOP}
x-scheme-handler/http=${ORIGIN_DESKTOP}
x-scheme-handler/https=${ORIGIN_DESKTOP}
x-scheme-handler/about=${ORIGIN_DESKTOP}
x-scheme-handler/unknown=${ORIGIN_DESKTOP}
EOF
cp /usr/share/applications/mimeapps.list /usr/etc/xdg/mimeapps.list

# Point KDE at Brave without wiping the rest of kdeglobals.
for kg in \
  /usr/etc/xdg/kdeglobals \
  /etc/xdg/kdeglobals \
  /usr/share/kde-settings/kde-profile/default/share/config/kdeglobals
do
  [[ -f "$kg" ]] || continue
  if grep -q '^BrowserApplication=' "$kg"; then
    sed -i "s/^BrowserApplication=.*/BrowserApplication=${ORIGIN_DESKTOP}/" "$kg"
  elif grep -q '^\[General\]' "$kg"; then
    sed -i "/^\\[General\\]/a BrowserApplication=${ORIGIN_DESKTOP}" "$kg"
  else
    printf '\n[General]\nBrowserApplication=%s\n' "${ORIGIN_DESKTOP}" >> "$kg"
  fi
done

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
fi

if command -v glib-compile-schemas >/dev/null && [[ -d /usr/share/glib-2.0/schemas ]]; then
  glib-compile-schemas /usr/share/glib-2.0/schemas || true
fi
