#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
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

# Every new libexec file is executable. Do not keep a name list.
find /usr/libexec/unwoke -maxdepth 1 -type f -exec chmod a+x {} + 2>/dev/null || true

# Stock #1606: PEM blocklist of Fedora CAs not in the Mozilla website set.
if [[ -x /usr/libexec/unwoke/ca-trim-build.py ]] || [[ -f /usr/libexec/unwoke/ca-trim-build.py ]]; then
  python3 /usr/libexec/unwoke/ca-trim-build.py || echo "ca-trim-build: skipped"
fi

# mark-check.py runs after vendor desktops/help stubs so those are marked too.
if [[ ! -f /usr/libexec/unwoke/mark-check.py ]]; then
  echo "FAIL: missing /usr/libexec/unwoke/mark-check.py" >&2
  exit 1
fi

# One .desktop per vendors{} key + missing offline help stubs from the same JSON.
# Fail compose if the list is empty or invalid so the image cannot ship half-synced.
python3 - <<'PY'
import html
import json
from pathlib import Path

p = Path("/usr/share/unwoke/vendor-installers.json")
if not p.is_file():
    raise SystemExit("FAIL: missing vendor-installers.json")
vendors = json.loads(p.read_text(encoding="utf-8")).get("vendors") or {}
if not vendors:
    raise SystemExit("FAIL: vendors{} empty")
dstdir = Path("/usr/share/applications")
dstdir.mkdir(parents=True, exist_ok=True)
help_root = Path("/usr/share/unwoke/help")
slugs = {}
for name, spec in vendors.items():
    if not spec.get("kind"):
        raise SystemExit(f"FAIL: vendor {name} missing kind")
    title = spec.get("title") or name
    kw = spec.get("keywords") or name.replace("_", ";")
    body = f"""# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
[Desktop Entry]
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
    slug = spec.get("tutorial") or spec.get("group") or name.replace("_", "-")
    slugs.setdefault(slug, []).append((name, spec))
help_root.mkdir(parents=True, exist_ok=True)
for slug, items in slugs.items():
    dest = help_root / slug / "index.html"
    if dest.is_file():
        continue
    dest.parent.mkdir(parents=True, exist_ok=True)
    titles = [spec.get("title") or n for n, spec in items]
    h1 = html.escape(titles[0] if len(titles) == 1 else slug.replace("-", " ").title())
    lis = []
    for n, spec in items:
        t = html.escape(spec.get("title") or n)
        lis.append(f"<li><strong>{t}</strong> — <code>ujust install-vendor {html.escape(n)}</code></li>")
    dest.write_text(
        f"""<!DOCTYPE html>
<!-- Unwoke SecureBlue. Not affiliated with secureblue. MIT License. Copyright (c) 2026 SeRgi270710267. UNWOKE-SHIPPED-FIRST. -->
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{h1} | Unwoke help</title>
  <link rel="stylesheet" href="../css/main.css">
</head>
<body>
  <nav id="site-menu" aria-label="Primary">
    <ul>
      <li><a href="../index.html">Unwoke help (offline)</a></li>
    </ul>
  </nav>
  <main>
    <h1>{h1}</h1>
    <p>Generated from <code>vendor-installers.json</code>. Nothing auto-unlocks. No store.</p>
    <ul>
      {"".join(lis)}
    </ul>
  </main>
</body>
</html>
""",
        encoding="utf-8",
    )
    print(f"vendor help stub {dest}")
print(f"vendor desktops {len(vendors)}; help slugs {len(slugs)}")
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
[[ -f /usr/share/unwoke/NOTICE && -f /usr/share/unwoke/LICENSE ]] || {
  echo "FAIL: missing /usr/share/unwoke/NOTICE or LICENSE" >&2
  exit 1
}
# Stamp first so a new overlay file is marked without a human reminder.
# Live Chromium/Brave/Trivalent managed JSON is scrubbed, not stamped.
python3 /usr/libexec/unwoke/mark-check.py --apply /

# Pre-flavor RPM sqlite. Origin extra dnf (Brave + selinux-policy-devel)
# can malform Packages so titanoboa dnf dies. Flavor scripts restore this
# copy if Packages is unreadable, then delete it so it does not ship.
bak=/usr/share/unwoke/.rpmdb-pre-flavor.sqlite
rm -f "${bak}"
for db in /usr/lib/sysimage/rpm/rpmdb.sqlite /usr/share/rpm/rpmdb.sqlite /var/lib/rpm/rpmdb.sqlite; do
  [[ -f "${db}" ]] || continue
  cp -a "${db}" "${bak}"
  echo "unwoke: saved pre-flavor rpmdb from ${db}"
  break
done
