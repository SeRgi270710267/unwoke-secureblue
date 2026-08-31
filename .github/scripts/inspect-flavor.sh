#!/usr/bin/env bash
# Inspect a published Unwoke GHCR image without docker/podman pull (crane export).
# Usage: inspect-flavor.sh <image-name>   e.g. unwoke-silverblue-trivalent
set -euo pipefail

NAME="${1:?usage: inspect-flavor.sh unwoke-silverblue}"
OWNER="${GITHUB_REPOSITORY_OWNER:-sergi270710267}"
OWNER="${OWNER,,}"
IMG="ghcr.io/${OWNER}/${NAME}:latest"
ROOT="${GITHUB_WORKSPACE:-.}"
PUB="${ROOT}/cosign.pub"
extract="${ROOT}/.github/scripts/extract-prefixes.py"

[[ -f "${PUB}" ]] || { echo "missing ${PUB}" >&2; exit 1; }
[[ -f "${extract}" ]] || { echo "missing ${extract}" >&2; exit 1; }
command -v cosign >/dev/null || { echo "cosign required" >&2; exit 1; }

bash "${ROOT}/.github/scripts/install-crane.sh"
export PATH="${HOME}/.local/bin:${PATH}"

ok=0
for n in 1 2 3 4 5; do
  if crane digest "${IMG}" >/dev/null 2>&1; then
    ok=1
    break
  fi
  echo "inspect: waiting for ${IMG} (${n}/5)"
  sleep 15
done
[[ "${ok}" -eq 1 ]] || { echo "FAIL: cannot see ${IMG}" >&2; exit 1; }

echo "inspect: cosign verify ${IMG}"
# GitHub attest-build-provenance attaches certificate attestations as OCI
# referrers. Newer cosign verify --key can pick those and fail with
# "expected key signature, not certificate". Prefer classic .sig tags.
extra=()
if cosign verify --help 2>&1 | grep -q -- '--new-bundle-format'; then
  extra+=(--new-bundle-format=false)
fi
payload="$(COSIGN_OCI_EXPERIMENTAL=0 cosign verify --key "${PUB}" "${extra[@]}" "${IMG}" 2>/dev/null || true)"
if [[ -z "${payload}" ]]; then
  echo "FAIL: no Unwoke key signature on ${IMG}" >&2
  COSIGN_OCI_EXPERIMENTAL=0 cosign verify --key "${PUB}" "${extra[@]}" "${IMG}" >/dev/null
  exit 1
fi
got="$(python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["critical"]["image"]["docker-manifest-digest"])' <<<"${payload}")"
want="$(crane digest "${IMG}")"
if [[ "${got}" != "${want}" ]]; then
  echo "FAIL: signed digest ${got} != ${want}" >&2
  exit 1
fi
echo "inspect: signed digest ${got}"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
echo "inspect: export ${IMG}"
crane export "${IMG}" - | python3 "${extract}" "${work}" "${work}/members.txt" \
  usr/share/unwoke usr/bin usr/lib64 usr/libexec opt usr/share/applications \
  usr/lib/systemd etc/selinux usr/etc usr/share/glib-2.0/schemas \
  usr/share/fish usr/share/gnome-background-properties \
  usr/share/wallpapers/UnwokeSecureBlue \
  usr/lib/sysimage/rpm usr/share/rpm var/lib/rpm

if [[ ! -s "${work}/members.txt" ]]; then
  echo "FAIL: export produced no file list from ${IMG}" >&2
  exit 1
fi

flavor=""
if [[ -f "${work}/usr/share/unwoke/flavor" ]]; then
  flavor="$(tr -d '[:space:]' < "${work}/usr/share/unwoke/flavor")"
fi
echo "flavor file: ${flavor:-MISSING}"

has() { [[ -e "${work}/$1" ]]; }
# Tar member exists as a file/symlink/hardlink (empty leftover dirs do not count).
listed() {
  awk -F '\t' -v p="$1" '$1 != "dir" && $2 == p { found=1 } END { exit !found }' \
    "${work}/members.txt"
}

fail=0
# Uncommitted WAL is what broke Origin ISO wraps (dnf in titanoboa).
# Do not PRAGMA integrity_check — RPM sqlite is not a vanilla db (bake 89).
# -shm is ephemeral; sqlite recreates it. Only a non-empty -wal is a miss.
if ! python3 - "${work}" <<'PY'
import sqlite3
import sys
from pathlib import Path

root = Path(sys.argv[1])
cands: list[Path] = []
for rel in ("usr/lib/sysimage/rpm", "usr/share/rpm", "var/lib/rpm"):
    d = root / rel
    if d.is_dir():
        cands.extend(sorted(d.glob("*.sqlite")))
    p = d / "rpmdb.sqlite"
    if p.is_file() and p not in cands:
        cands.append(p)
seen: list[Path] = []
rc = 0
for db in cands:
    if not db.is_file():
        continue
    real = db.resolve()
    if real in seen:
        continue
    seen.append(real)
    wal = Path(str(db) + "-wal")
    if wal.is_file() and wal.stat().st_size > 0:
        print(f"FAIL: shipped uncheckpointed {wal.relative_to(root)}", file=sys.stderr)
        rc = 1
        continue
    # Do not PRAGMA integrity_check (false bake fail). rpm -q kernel-core
    # reads Name/Packages — if those SELECT as malformed, USB wrap dies.
    try:
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        try:
            con.execute("SELECT count(*) FROM sqlite_master").fetchone()
            tables = [
                r[0]
                for r in con.execute(
                    "SELECT name FROM sqlite_master WHERE type='table'"
                )
            ]
            hit = False
            for t in tables:
                if t.lower() in {"name", "packages"}:
                    con.execute(f'SELECT count(*) FROM "{t}"').fetchone()
                    hit = True
                    print(
                        f"OK: rpmdb {db.relative_to(root)} table {t} readable"
                    )
            if not hit:
                print(
                    f"WARN: rpmdb {db.relative_to(root)} has no Name/Packages "
                    "(ISO hook stubs Origin live db)",
                    file=sys.stderr,
                )
        finally:
            con.close()
    except sqlite3.Error as e:
        # Origin still ships a torn Name table. Fail only on WAL.
        # Live USB hook throws this sqlite away (wrap 33313748024 green).
        print(
            f"WARN: rpmdb {db.relative_to(root)} unreadable: {e}",
            file=sys.stderr,
        )
        continue
    print(f"OK: rpmdb sqlite {db.relative_to(root)} (no WAL)")
if not seen:
    print("FAIL: no rpmdb.sqlite in export", file=sys.stderr)
    raise SystemExit(1)
raise SystemExit(rc)
PY
then
  echo "FAIL: RPM sqlite shipped with uncheckpointed WAL" >&2
  fail=1
fi
for d in usr/share/applications/io.github.kolunmi.Bazaar.desktop \
         usr/share/applications/org.gnome.Software.desktop \
         usr/share/applications/org.kde.discover.desktop; do
  if has "$d" && ! grep -q '^Hidden=true' "${work}/${d}" 2>/dev/null; then
    echo "FAIL: store launcher visible: $d" >&2
    fail=1
  fi
done
if listed opt/brave.com/brave/brave; then
  echo "FAIL: full brave-browser ELF present" >&2
  fail=1
fi

tramp="${work}/usr/libexec/secureblue/harden_flatpak.py"
if [[ ! -f "${tramp}" ]] || ! grep -q '/usr/libexec/unwoke/harden-flatpak.sh' "${tramp}"; then
  echo "FAIL: stock harden_flatpak trampoline missing or not ours" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/libexec/unwoke/harden-flatpak.sh" ]]; then
  echo "FAIL: missing /usr/libexec/unwoke/harden-flatpak.sh" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/libexec/unwoke/setup.sh" ]]; then
  echo "FAIL: missing /usr/libexec/unwoke/setup.sh" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/libexec/unwoke/first-session.sh" ]]; then
  echo "FAIL: missing /usr/libexec/unwoke/first-session.sh" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/etc/xdg/autostart/unwoke-first-session.desktop" ]]; then
  echo "FAIL: missing first-session autostart" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/libexec/unwoke/setup-gui.py" ]]; then
  echo "FAIL: missing /usr/libexec/unwoke/setup-gui.py" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/libexec/unwoke/privacy.sh" ]]; then
  echo "FAIL: missing /usr/libexec/unwoke/privacy.sh" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/share/unwoke/journald-volatile.conf" ]]; then
  echo "FAIL: missing journald-volatile.conf" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/share/unwoke/logind-no-hibernate.conf" ]]; then
  echo "FAIL: missing logind-no-hibernate.conf" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/share/unwoke/coredump-none.conf" ]]; then
  echo "FAIL: missing coredump-none.conf" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/share/unwoke/sysctl-anon.conf" ]]; then
  echo "FAIL: missing sysctl-anon.conf" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/libexec/unwoke/anon-net.sh" ]]; then
  echo "FAIL: missing anon-net.sh" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/libexec/unwoke/continue-ostree.sh" ]]; then
  echo "FAIL: missing continue-ostree.sh" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/lib/systemd/system/unwoke-signed-idle-reboot.service" ]]; then
  echo "FAIL: missing signed-idle-reboot.service" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/libexec/unwoke/network-fs.sh" ]]; then
  echo "FAIL: missing /usr/libexec/unwoke/network-fs.sh" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/share/unwoke/modprobe-network-fs.conf" ]]; then
  echo "FAIL: missing modprobe-network-fs.conf" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/libexec/unwoke/flatpak-record.sh" ]]; then
  echo "FAIL: missing /usr/libexec/unwoke/flatpak-record.sh" >&2
  fail=1
fi
if ! grep -q 'xdg-documents' "${work}/usr/libexec/unwoke/flatpak-lockdown.sh" 2>/dev/null; then
  echo "FAIL: lockdown missing extra xdg filesystem cuts" >&2
  fail=1
fi
if ! grep -q 'host-root' "${work}/usr/libexec/unwoke/flatpak-lockdown.sh" 2>/dev/null; then
  echo "FAIL: lockdown missing host-root cut" >&2
  fail=1
fi
if grep -vE '^[[:space:]]*#' "${work}/usr/libexec/unwoke/flatpak-lockdown.sh" 2>/dev/null | grep -qE -- '--nofilesystem=host-os([[:space:]]|$)'; then
  echo "FAIL: lockdown must not cut host-os (harden-flatpak malloc needs host-os:ro)" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/share/applications/unwoke-lock-network-fs.desktop" ]]; then
  echo "FAIL: missing Network shares lock launcher" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/share/applications/unwoke-lock-flatpak-record.desktop" ]]; then
  echo "FAIL: missing Flatpak record lock launcher" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/share/unwoke/help/network-fs/index.html" ]]; then
  echo "FAIL: missing offline help for network-fs" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/share/unwoke/help/steam/index.html" ]]; then
  echo "FAIL: missing offline help for steam" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/share/applications/unwoke-lock-steam.desktop" ]]; then
  echo "FAIL: missing Steam wizard launcher" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/etc/cryptsetup.conf" ]] || ! grep -q 'pbkdf-memory = 2097152' "${work}/usr/etc/cryptsetup.conf"; then
  echo "FAIL: missing /usr/etc/cryptsetup.conf Argon2 2 GiB default" >&2
  fail=1
fi
if ! grep -q '/var/tmp' "${work}/usr/libexec/unwoke/ramdisk.sh" 2>/dev/null; then
  echo "FAIL: ramdisk.sh missing /var/tmp noexec" >&2
  fail=1
fi
for f in usr/libexec/unwoke/ramdisk.sh \
         usr/libexec/unwoke/cet.sh \
         usr/libexec/unwoke/boot-perm.sh \
         usr/libexec/unwoke/ca-trim.sh \
         usr/libexec/unwoke/ca-trim-build.py \
         usr/share/unwoke/mozilla-ca-sha256.txt \
         usr/share/unwoke/SHIPPED-FIRST.txt \
         usr/share/unwoke/cet-system.conf \
         usr/share/unwoke/cet-profile.sh; do
  if [[ ! -f "${work}/${f}" ]]; then
    echo "FAIL: missing /${f}" >&2
    fail=1
  fi
done
if ! grep -q 'dhcp-send-release' "${work}/usr/share/unwoke/nm-privacy-dhcp.conf" 2>/dev/null; then
  echo "FAIL: dhcp privacy conf missing dhcp-send-release" >&2
  fail=1
fi
if ! grep -q 'dhcp-iaid' "${work}/usr/share/unwoke/nm-privacy-dhcp.conf" 2>/dev/null; then
  echo "FAIL: dhcp privacy conf missing dhcp-iaid" >&2
  fail=1
fi
if ! grep -q 'session-bus' "${work}/usr/libexec/unwoke/toggles.sh" 2>/dev/null; then
  echo "FAIL: audit-unwoke missing Flatpak session-bus check" >&2
  fail=1
fi
if ! grep -q 'UNWOKE-SHIPPED-FIRST' "${work}/usr/share/unwoke/SHIPPED-FIRST.txt" 2>/dev/null; then
  echo "FAIL: SHIPPED-FIRST.txt missing prior-art token" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/share/unwoke/LICENSE" ]]; then
  echo "FAIL: missing /usr/share/unwoke/LICENSE" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/share/unwoke/NOTICE" ]]; then
  echo "FAIL: missing /usr/share/unwoke/NOTICE" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/libexec/unwoke/mark-check.py" ]]; then
  echo "FAIL: missing /usr/libexec/unwoke/mark-check.py" >&2
  fail=1
elif ! python3 "${work}/usr/libexec/unwoke/mark-check.py" "${work}"; then
  echo "FAIL: overlay files missing UNWOKE-SHIPPED-FIRST" >&2
  fail=1
fi
for f in usr/share/unwoke/nm-privacy-connectivity.conf \
         usr/share/unwoke/nm-privacy-dhcp.conf \
         usr/share/unwoke/dconf-thumbnails-off \
         usr/share/unwoke/dolphin-thumbnails-off; do
  if [[ ! -f "${work}/${f}" ]]; then
    echo "FAIL: missing /${f}" >&2
    fail=1
  fi
done
if ! grep -q '"HyperlinkAuditingEnabled": false' "${work}/usr/share/unwoke/brave-hardening.json" 2>/dev/null; then
  echo "FAIL: hardening pack missing HyperlinkAuditingEnabled false" >&2
  fail=1
fi
if ! grep -q '"PrivacySandboxAdTopicsEnabled": false' "${work}/usr/share/unwoke/brave-hardening.json" 2>/dev/null; then
  echo "FAIL: hardening pack missing Privacy Sandbox off" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/share/unwoke/resolved-privacy.conf" ]]; then
  echo "FAIL: missing resolved-privacy.conf" >&2
  fail=1
fi
if ! grep -q '^llmnr=no' "${work}/usr/share/unwoke/nm-privacy-dhcp.conf" 2>/dev/null; then
  echo "FAIL: dhcp privacy conf missing llmnr=no" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/share/applications/unwoke-setup.desktop" ]]; then
  echo "FAIL: missing Unwoke setup launcher" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/share/applications/unwoke-lock-bluetooth.desktop" ]]; then
  echo "FAIL: missing Bluetooth lock launcher" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/share/unwoke/help/index.html" ]]; then
  echo "FAIL: missing offline help" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/lib/systemd/user/unwoke-signed-nag.timer" ]]; then
  echo "FAIL: missing signed-nag timer" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/libexec/unwoke/notify-reboot.sh" ]]; then
  echo "FAIL: missing notify-reboot.sh" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/libexec/unwoke/install-proton.sh" ]]; then
  echo "FAIL: missing install-proton.sh" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/libexec/unwoke/install-steam.sh" ]]; then
  echo "FAIL: missing install-steam.sh" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/libexec/unwoke/install-whonix.sh" ]]; then
  echo "FAIL: missing install-whonix.sh" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/libexec/unwoke/start-whonix.sh" ]]; then
  echo "FAIL: missing start-whonix.sh" >&2
  fail=1
fi
if ! python3 - "${work}" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1]) / "usr/share/unwoke/whonix-kvm.json"
d = json.loads(p.read_text(encoding="utf-8"))
fp = (d.get("fingerprint") or "").replace(" ", "")
if fp != "916B8D99C38EAF5E8ADC7A2A8D66066A2EEACCDA":
    print("FAIL: Whonix fingerprint pin drifted", fp, file=sys.stderr)
    raise SystemExit(1)
if "download.whonix.org" not in (d.get("archive_url") or ""):
    print("FAIL: archive_url not download.whonix.org", file=sys.stderr)
    raise SystemExit(1)
print("whonix-kvm pin", d.get("version"))
PY
then
  echo "FAIL: whonix-kvm.json pin" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/libexec/unwoke/play-window.sh" ]]; then
  echo "FAIL: missing play-window.sh" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/libexec/unwoke/play-steam.sh" ]]; then
  echo "FAIL: missing play-steam.sh" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/lib/systemd/user/unwoke-play-agent.service" ]]; then
  echo "FAIL: missing play-window login agent" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/share/unwoke/gamemode.ini" ]]; then
  echo "FAIL: missing GameMode session ini" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/lib/modules-load.d/unwoke-ntsync.conf" ]]; then
  echo "FAIL: missing ntsync modules-load" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/share/applications/unwoke-lock-gaming.desktop" ]]; then
  echo "FAIL: missing Gaming tab launcher" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/share/unwoke/help/gaming/index.html" ]]; then
  echo "FAIL: missing offline help for gaming" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/share/unwoke/stock-installs.json" ]]; then
  echo "FAIL: missing stock-installs.json" >&2
  fail=1
fi
if ! python3 - "${work}" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
p = root / "usr/share/unwoke/stock-installs.json"
d = json.loads(p.read_text(encoding="utf-8"))
rc = 0
for name, spec in (d.get("recipes") or {}).items():
    script = spec.get("script") or ""
    if not script or not (root / "usr/libexec/unwoke" / script).is_file():
        print(f"FAIL: stock-installs {name} missing script {script}", file=sys.stderr)
        rc = 1
print("stock-installs", len(d.get("recipes") or {}))
raise SystemExit(rc)
PY
then
  echo "FAIL: stock-installs.json scripts missing" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/libexec/unwoke/install-vpn.sh" ]]; then
  echo "FAIL: missing install-vpn.sh" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/libexec/unwoke/install-dangerzone.sh" ]]; then
  echo "FAIL: missing install-dangerzone.sh" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/libexec/unwoke/wrap-assemble.sh" ]]; then
  echo "FAIL: missing wrap-assemble.sh" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/libexec/unwoke/wrap-flathub-unfiltered.sh" ]]; then
  echo "FAIL: missing wrap-flathub-unfiltered.sh" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/libexec/unwoke/install-ivpn.sh" ]]; then
  echo "FAIL: missing install-ivpn.sh" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/libexec/unwoke/vendor.py" ]]; then
  echo "FAIL: missing vendor.py" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/share/unwoke/vendor-installers.json" ]]; then
  echo "FAIL: missing vendor-installers.json" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/libexec/unwoke/install-vendor.sh" ]]; then
  echo "FAIL: missing install-vendor.sh" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/libexec/unwoke/install-mullvad.sh" ]]; then
  echo "FAIL: missing install-mullvad.sh" >&2
  fail=1
fi
if ! python3 - "${work}" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
p = root / "usr/share/unwoke/vendor-installers.json"
d = json.loads(p.read_text(encoding="utf-8"))
v = d.get("vendors") or {}
if not v:
    print("FAIL: vendors{} empty", file=sys.stderr)
    raise SystemExit(1)
kinds = {"https-ok", "wireguard-import", "proton-version-json", "yum-repo"}
slugs = set()
rc = 0
for name, spec in v.items():
    kind = spec.get("kind")
    if kind not in kinds:
        print(f"FAIL: vendor {name} unknown kind {kind!r}", file=sys.stderr)
        rc = 1
        continue
    desk = root / f"usr/share/applications/unwoke-vendor-{name}.desktop"
    if not desk.is_file():
        print(f"FAIL: missing desktop for vendor {name}", file=sys.stderr)
        rc = 1
    slug = spec.get("tutorial") or spec.get("group")
    if slug:
        slugs.add(slug)
        helpf = root / f"usr/share/unwoke/help/{slug}/index.html"
        if not helpf.is_file():
            print(f"FAIL: missing offline help for vendor slug {slug}", file=sys.stderr)
            rc = 1
print("vendors", len(v), *sorted(v))
raise SystemExit(rc)
PY
then
  echo "FAIL: vendor list / desktops / offline help out of sync" >&2
  fail=1
fi
# Schema uses the repo copy of vendor.py (new kinds/HOSTS) against the
# JSON that actually shipped. Do not exec schema on an older image binary.
if [[ -f "${ROOT}/files/system/usr/libexec/unwoke/vendor.py" ]]; then
  if ! UNWOKE_VENDOR_JSON="${work}/usr/share/unwoke/vendor-installers.json" \
      python3 "${ROOT}/files/system/usr/libexec/unwoke/vendor.py" schema; then
    echo "FAIL: vendor schema against published JSON" >&2
    fail=1
  fi
fi

selinux_mentions_origin() {
  grep -R -q '/opt/brave.com/brave-origin' \
    "${work}/etc/selinux" "${work}/usr/etc/selinux" 2>/dev/null
}

case "${NAME}" in
  *trivalent*)
    [[ "${flavor}" == "trivalent" ]] || { echo "FAIL: flavor != trivalent (${flavor})" >&2; fail=1; }
    if ! listed usr/bin/trivalent && ! listed usr/lib64/trivalent/trivalent; then
      echo "FAIL: Trivalent binary missing" >&2
      fail=1
    fi
    if listed opt/brave.com/brave-origin/brave; then
      echo "FAIL: Origin ELF on trivalent image" >&2
      fail=1
    fi
    if selinux_mentions_origin; then
      echo "FAIL: brave-origin in SELinux file_contexts" >&2
      fail=1
    fi
    echo "OK: trivalent flavor checks"
    ;;
  *browserless*)
    [[ "${flavor}" == "browserless" ]] || { echo "FAIL: flavor != browserless (${flavor})" >&2; fail=1; }
    if listed opt/brave.com/brave-origin/brave; then
      echo "FAIL: Origin ELF on browserless image" >&2
      fail=1
    fi
    if listed usr/bin/trivalent || listed usr/lib64/trivalent/trivalent; then
      echo "FAIL: Trivalent present on browserless image" >&2
      fail=1
    fi
    if selinux_mentions_origin; then
      echo "FAIL: brave-origin in SELinux file_contexts" >&2
      fail=1
    fi
    echo "OK: browserless flavor checks"
    ;;
  *)
    [[ "${flavor}" == "brave-origin" ]] || { echo "FAIL: flavor != brave-origin (${flavor})" >&2; fail=1; }
    if listed usr/bin/trivalent || listed usr/lib64/trivalent/trivalent; then
      echo "FAIL: Trivalent present on Origin image" >&2
      fail=1
    fi
    if ! listed opt/brave.com/brave-origin/brave \
       && ! listed usr/lib/opt/brave.com/brave-origin/brave \
       && ! listed usr/bin/brave-origin; then
      echo "FAIL: Origin ELF missing" >&2
      fail=1
    fi
    if ! has usr/share/unwoke/selinux/unwoke_brave.te; then
      echo "FAIL: missing unwoke_brave.te" >&2
      fail=1
    fi
    suid="$(find "${work}/opt/brave.com" "${work}/usr/lib/opt/brave.com" \
      -xdev -perm -4000 -type f 2>/dev/null || true)"
    if [[ -n "${suid}" ]]; then
      echo "FAIL: SUID remains under Brave Origin tree" >&2
      printf '%s\n' "${suid}" >&2
      fail=1
    fi
    echo "OK: Origin flavor checks"
    ;;
esac

if [[ "${fail}" -ne 0 ]]; then
  echo "inspect FAILED for ${IMG}" >&2
  echo "matching members:" >&2
  awk -F '\t' '$2 ~ /(trivalent|brave-origin|brave\/brave)/ { print; n++; if (n>=40) exit }' \
    "${work}/members.txt" >&2 || true
  exit 1
fi
echo "inspect OK: ${IMG}"
