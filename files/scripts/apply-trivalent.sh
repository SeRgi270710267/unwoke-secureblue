#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Trivalent flavor: keep stock Trivalent + trivalent-selinux. No brave_t.
# Extra Chromium managed policies land via first-boot / ujust.
set -oue pipefail

mkdir -p /usr/share/unwoke
printf 'trivalent\n' > /usr/share/unwoke/flavor

TRIV_DESKTOP="trivalent.desktop"
if [[ ! -f "/usr/share/applications/${TRIV_DESKTOP}" ]]; then
  for d in /usr/share/applications/trivalent*.desktop; do
    [[ -f "$d" ]] || continue
    TRIV_DESKTOP="$(basename "$d")"
    break
  done
fi

# Stock may have Hidden= leftover from an older overlay; unhide the house browser.
if [[ -f "/usr/share/applications/${TRIV_DESKTOP}" ]]; then
  sed -i '/^Hidden=/d' "/usr/share/applications/${TRIV_DESKTOP}" || true
fi

for d in brave-origin.desktop brave-browser.desktop \
         io.github.kolunmi.Bazaar.desktop org.gnome.Software.desktop \
         org.kde.discover.desktop; do
  if [[ -f "/usr/share/applications/${d}" ]]; then
    grep -q '^Hidden=' "/usr/share/applications/${d}" || echo 'Hidden=true' >> "/usr/share/applications/${d}"
  fi
done

mkdir -p /usr/share/applications /usr/etc/xdg
cat > /usr/share/applications/mimeapps.list <<EOF
[Default Applications]
text/html=${TRIV_DESKTOP}
application/xhtml+xml=${TRIV_DESKTOP}
x-scheme-handler/http=${TRIV_DESKTOP}
x-scheme-handler/https=${TRIV_DESKTOP}
x-scheme-handler/about=${TRIV_DESKTOP}
x-scheme-handler/unknown=${TRIV_DESKTOP}
EOF
cp /usr/share/applications/mimeapps.list /usr/etc/xdg/mimeapps.list

for kg in \
  /usr/etc/xdg/kdeglobals \
  /etc/xdg/kdeglobals \
  /usr/share/kde-settings/kde-profile/default/share/config/kdeglobals
do
  [[ -f "$kg" ]] || continue
  if grep -q '^BrowserApplication=' "$kg"; then
    sed -i "s/^BrowserApplication=.*/BrowserApplication=${TRIV_DESKTOP}/" "$kg"
  elif grep -q '^\[General\]' "$kg"; then
    sed -i "/^\\[General\\]/a BrowserApplication=${TRIV_DESKTOP}" "$kg"
  else
    printf '\n[General]\nBrowserApplication=%s\n' "${TRIV_DESKTOP}" >> "$kg"
  fi
done

# Compose-time managed policies + launcher flags (ostree /usr/etc → /etc).
SRC=/usr/share/unwoke
for dest in \
  /usr/etc/trivalent/policies/managed \
  /usr/etc/chromium/policies/managed
do
  mkdir -p "${dest}"
  for pack in \
    10-unwoke-hardening:brave-hardening.json \
    15-unwoke-devices:brave-devices.json \
    20-unwoke-jitless:brave-jitless.json \
    30-unwoke-extensions:brave-extensions.json \
    40-unwoke-isolation:brave-isolation.json \
    50-unwoke-sandbox:brave-sandbox.json
  do
    name="${pack%%:*}"
    srcf="${pack##*:}"
    [[ -f "${SRC}/${srcf}" ]] || continue
    python3 /usr/libexec/unwoke/mark-check.py --install-policy \
      "${SRC}/${srcf}" "${dest}/${name}.json"
  done
done

mkdir -p /usr/etc/trivalent/trivalent.conf.d
[[ -f "${SRC}/trivalent-isolation.conf" ]] && \
  cp -a "${SRC}/trivalent-isolation.conf" /usr/etc/trivalent/trivalent.conf.d/40-unwoke-isolation.conf
[[ -f "${SRC}/trivalent-network-sandbox.conf" ]] && \
  cp -a "${SRC}/trivalent-network-sandbox.conf" /usr/etc/trivalent/trivalent.conf.d/50-unwoke-network-sandbox.conf
[[ -f "${SRC}/trivalent-referrers.conf" ]] && \
  cp -a "${SRC}/trivalent-referrers.conf" /usr/etc/trivalent/trivalent.conf.d/60-unwoke-referrers.conf

if command -v glib-compile-schemas >/dev/null && [[ -d /usr/share/glib-2.0/schemas ]]; then
  glib-compile-schemas /usr/share/glib-2.0/schemas || true
fi

# Flavor copies land after apply-unwoke. Scrub live policies; stamp anything new.
python3 /usr/libexec/unwoke/mark-check.py --apply /

