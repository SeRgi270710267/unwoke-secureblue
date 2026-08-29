#!/usr/bin/env bash
# Shared build-time overlay: hide leftover Bazaar/store/full-Brave launchers.
# Flavor scripts hide or keep trivalent.desktop. Does not touch harden_userns.
set -oue pipefail

for d in io.github.kolunmi.Bazaar.desktop \
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

WRAP=/usr/libexec/unwoke/bin-wrap
REALDIR=/usr/libexec/unwoke/real-bin
mkdir -p "${REALDIR}"
if [[ -f "${WRAP}" ]]; then
  chmod a+x "${WRAP}"
  for n in toolbox distrobox distrobox-create distrobox-enter distrobox-list \
           distrobox-rm distrobox-stop distrobox-upgrade distrobox-ephemeral \
           distrobox-generate-entry distrobox-assemble distrobox-host-exec \
           distrobox-export distrobox-init distrobox-clone; do
    src=""
    [[ -e "/usr/bin/${n}" ]] && src="/usr/bin/${n}"
    [[ -z "${src}" && -e "/usr/sbin/${n}" ]] && src="/usr/sbin/${n}"
    [[ -n "${src}" ]] || continue
    if [[ -L "${src}" ]]; then
      case "$(readlink -f "${src}" 2>/dev/null || true)" in
        *unwoke/bin-wrap*) continue ;;
      esac
    fi
    mv "${src}" "${REALDIR}/${n}"
    ln -sf "${WRAP}" "${src}"
  done
fi

if command -v systemctl >/dev/null; then
  systemctl enable unwoke-first-boot.service || true
  systemctl enable unwoke-browser-guard.service || true
  systemctl --global enable unwoke-browser-guard.service || true
  systemctl --global enable unwoke-user-defaults.service || true
  systemctl --global enable unwoke-signed-nag.timer || true
  systemctl enable unwoke-admin-split-setup.service || true
fi

chmod a+x /usr/libexec/unwoke/setup.sh /usr/libexec/unwoke/first-session.sh \
  /usr/libexec/unwoke/setup-gui.py /usr/libexec/unwoke/signed-nag.sh \
  /usr/libexec/unwoke/notify-reboot.sh /usr/libexec/unwoke/open-tutorial.sh \
  /usr/libexec/unwoke/install-proton.sh /usr/libexec/unwoke/install-ivpn.sh \
  /usr/libexec/unwoke/install-mullvad.sh \
  /usr/libexec/unwoke/install-vendor.sh /usr/libexec/unwoke/vendor.py \
  /usr/libexec/unwoke/toggles.sh /usr/libexec/unwoke/first-boot.sh 2>/dev/null || true

# One .desktop per vendors{} key so GNOME/KDE search finds new apps without extra files.
python3 - <<'PY' || true
import json
from pathlib import Path
p = Path("/usr/share/unwoke/vendor-installers.json")
dstdir = Path("/usr/share/applications")
if p.is_file() and dstdir.is_dir():
    vendors = json.loads(p.read_text(encoding="utf-8")).get("vendors") or {}
    for name, spec in vendors.items():
        title = spec.get("title") or name
        kw = spec.get("keywords") or name.replace("_", ";")
        body = f"""[Desktop Entry]
Type=Application
Name={title} (Unwoke)
Comment=Strict installer from vendor-installers.json. Nothing auto-unlocks.
Exec=/usr/libexec/unwoke/install-vendor.sh {name}
Icon=/usr/share/pixmaps/unwoke-logo.svg
Terminal=true
Categories=Settings;
Keywords={kw};unwoke;vendor;
StartupNotify=true
"""
        (dstdir / f"unwoke-vendor-{name}.desktop").write_text(body, encoding="utf-8")
PY

if command -v glib-compile-schemas >/dev/null && [[ -d /usr/share/glib-2.0/schemas ]]; then
  glib-compile-schemas /usr/share/glib-2.0/schemas || true
fi

# Stock `ujust harden-flatpak` execs this path. Overlay file must win over the RPM.
tramp="/usr/libexec/secureblue/harden_flatpak.py"
if [[ ! -f "${tramp}" ]] || ! grep -q '/usr/libexec/unwoke/harden-flatpak.sh' "${tramp}"; then
  echo "FAIL: ${tramp} is not the Unwoke trampoline" >&2
  exit 1
fi
[[ -f /usr/libexec/unwoke/harden-flatpak.sh ]] || {
  echo "FAIL: missing /usr/libexec/unwoke/harden-flatpak.sh" >&2
  exit 1
}
