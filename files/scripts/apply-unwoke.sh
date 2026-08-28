#!/usr/bin/env bash
# Runs at image build time. Makes Brave the default browser, hides leftover
# Trivalent/Bazaar/store launchers. Does not touch harden_userns.
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

swap_desktop "trivalent.desktop" "brave-browser.desktop"
swap_desktop "org.mozilla.firefox.desktop" "brave-browser.desktop"

mkdir -p /usr/share/applications /usr/etc/xdg
cat > /usr/share/applications/mimeapps.list <<'EOF'
[Default Applications]
text/html=brave-browser.desktop
application/xhtml+xml=brave-browser.desktop
x-scheme-handler/http=brave-browser.desktop
x-scheme-handler/https=brave-browser.desktop
x-scheme-handler/about=brave-browser.desktop
x-scheme-handler/unknown=brave-browser.desktop
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
    sed -i 's/^BrowserApplication=.*/BrowserApplication=brave-browser.desktop/' "$kg"
  elif grep -q '^\[General\]' "$kg"; then
    sed -i '/^\[General\]/a BrowserApplication=brave-browser.desktop' "$kg"
  else
    printf '\n[General]\nBrowserApplication=brave-browser.desktop\n' >> "$kg"
  fi
done

for d in trivalent.desktop io.github.kolunmi.Bazaar.desktop \
         org.gnome.Software.desktop org.kde.discover.desktop; do
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
