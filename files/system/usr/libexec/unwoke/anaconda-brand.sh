#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Brand Anaconda on the live USB. No-op if anaconda-live is not installed
# (normal ostree). Safe to run from apply-unwoke and from ISO prep_rootfs.
set -euo pipefail

MARK="# UNWOKE-ANACONDA-BRAND"
GTK_EXTRA="/usr/share/unwoke/anaconda-gtk-extra.css"
WEB_EXTRA="/usr/share/unwoke/anaconda-webui.css"
LOGO="/usr/share/pixmaps/unwoke-logo.svg"
WRAP="/usr/libexec/unwoke/liveinst-dark"

append_once() {
  local dst="$1" src="$2"
  [[ -f "${dst}" && -f "${src}" ]] || return 0
  if grep -qF "${MARK}" "${dst}"; then
    return 0
  fi
  {
    echo ""
    echo "/* ${MARK} */"
    cat "${src}"
  } >> "${dst}"
}

if [[ ! -d /usr/share/anaconda && ! -x /usr/sbin/liveinst ]]; then
  exit 0
fi

if [[ -f /usr/share/anaconda/anaconda-gtk.css ]]; then
  append_once /usr/share/anaconda/anaconda-gtk.css "${GTK_EXTRA}"
fi

if [[ -f "${LOGO}" ]]; then
  mkdir -p /usr/share/anaconda/pixmaps
  ln -sfn "${LOGO}" /usr/share/anaconda/pixmaps/sidebar-logo.svg 2>/dev/null || true
  ln -sfn "${LOGO}" /usr/share/anaconda/pixmaps/sidebar-logo.png 2>/dev/null || true
fi

# Web UI (Fedora 42+): Cockpit branding next to distro files.
if [[ -d /usr/share/cockpit/branding ]]; then
  while IFS= read -r -d '' css; do
    append_once "${css}" "${WEB_EXTRA}"
  done < <(find /usr/share/cockpit/branding -name 'branding.css' -print0 2>/dev/null || true)
fi

# Point "Install to Hard Drive" at the dark wrapper.
if [[ -x "${WRAP}" ]]; then
  while IFS= read -r -d '' desk; do
    grep -q '^Exec=' "${desk}" || continue
    grep -q 'liveinst-dark' "${desk}" && continue
    sed -i 's|^Exec=.*liveinst.*|Exec=/usr/libexec/unwoke/liveinst-dark|' "${desk}" 2>/dev/null || true
  done < <(find /usr/share/applications /usr/share/anaconda \( -name '*liveinst*.desktop' -o -name '*AnacondaInstaller*.desktop' \) -print0 2>/dev/null || true)
fi

# Show Install in the grid (Fedora hides liveinst with NoDisplay=true).
if [[ -x "${WRAP}" ]]; then
  cat > /usr/share/applications/unwoke-install.desktop <<EOF
# Unwoke SecureBlue. UNWOKE-SHIPPED-FIRST. Live USB only.
[Desktop Entry]
Type=Application
Name=Install Unwoke SecureBlue
GenericName=Install
Comment=Empty disk. Dark Unwoke Anaconda. Encrypts by default.
Exec=/usr/libexec/unwoke/liveinst-dark
Icon=/usr/share/pixmaps/unwoke-logo.svg
Terminal=false
Categories=System;Settings;
Keywords=install;anaconda;usb;unwoke;
StartupNotify=true
NoDisplay=false
EOF
  while IFS= read -r -d '' desk; do
    sed -i \
      -e 's/^NoDisplay=.*/NoDisplay=false/' \
      -e 's/^Name=.*/Name=Install Unwoke SecureBlue/' \
      "${desk}" 2>/dev/null || true
  done < <(find /usr/share/applications /usr/share/anaconda \( -name '*liveinst*.desktop' -o -name '*AnacondaInstaller*.desktop' \) -print0 2>/dev/null || true)
fi

# Live GNOME dash: Install first (setup is disabled on the USB).
if [[ -f /usr/share/applications/liveinst.desktop || -f /usr/share/applications/unwoke-install.desktop ]]; then
  cat > /usr/share/glib-2.0/schemas/zz3-unwoke-liveinst.gschema.override <<'EOF'
# Unwoke SecureBlue. UNWOKE-SHIPPED-FIRST. Live USB only.
[org.gnome.shell]
favorite-apps = ['unwoke-install.desktop', 'liveinst.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Ptyxis.desktop']
EOF
  glib-compile-schemas /usr/share/glib-2.0/schemas >/dev/null 2>&1 || true
fi

exit 0
