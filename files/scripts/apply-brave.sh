#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Brave Origin flavor: default browser + flavor stamp. SELinux is a later script.
set -oue pipefail

mkdir -p /usr/share/unwoke
printf 'brave-origin\n' > /usr/share/unwoke/flavor

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

# Desktop Exec goes through the wrapper so Bubblejail can be toggled later.
if [[ -f "/usr/share/applications/${ORIGIN_DESKTOP}" ]]; then
  sed -i -E \
    -e 's|^Exec=.*/brave-origin/brave|Exec=/usr/libexec/unwoke/brave-origin-launch|' \
    -e 's|^Exec=/usr/bin/brave-origin|Exec=/usr/libexec/unwoke/brave-origin-launch|' \
    "/usr/share/applications/${ORIGIN_DESKTOP}" || true
fi

swap_desktop "trivalent.desktop" "${ORIGIN_DESKTOP}"
swap_desktop "brave-browser.desktop" "${ORIGIN_DESKTOP}"
swap_desktop "org.mozilla.firefox.desktop" "${ORIGIN_DESKTOP}"

for d in trivalent.desktop brave-browser.desktop \
         io.github.kolunmi.Bazaar.desktop org.gnome.Software.desktop \
         org.kde.discover.desktop; do
  if [[ -f "/usr/share/applications/${d}" ]]; then
    grep -q '^Hidden=' "/usr/share/applications/${d}" || echo 'Hidden=true' >> "/usr/share/applications/${d}"
  fi
done

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
