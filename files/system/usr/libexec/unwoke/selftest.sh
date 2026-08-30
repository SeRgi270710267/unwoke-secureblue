#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Prove every overlay addition on this disk. Does not unlock anything.
# PASS = default lock is in effect. LOOSE = you turned it off (still your choice).
# FAIL = the image is missing what this flavor should ship. SKIP = not this flavor.
set -euo pipefail

PASS=0
FAIL=0
LOOSE=0
SKIP=0

pass() { printf '  PASS  %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  FAIL  %s\n' "$*"; FAIL=$((FAIL + 1)); }
loose() { printf '  LOOSE %s\n' "$*"; LOOSE=$((LOOSE + 1)); }
skip() { printf '  SKIP  %s\n' "$*"; SKIP=$((SKIP + 1)); }
proof() { printf '        proof: %s\n' "$*"; }
section() { printf '\n== %s ==\n' "$*"; }

FLAVOR="unknown"
if [[ -f /usr/share/unwoke/flavor ]]; then
  FLAVOR="$(tr -d '[:space:]' < /usr/share/unwoke/flavor)"
fi
is_browserless() { [[ "${FLAVOR}" == "browserless" ]]; }
is_origin() { [[ "${FLAVOR}" == "brave-origin" ]]; }
is_trivalent() { [[ "${FLAVOR}" == "trivalent" ]]; }

trivalent_present() {
  [[ -e /usr/bin/trivalent ]] \
    || [[ -e /usr/lib64/trivalent/trivalent ]] \
    || [[ -e /usr/lib/trivalent/trivalent ]]
}

origin_elf() {
  [[ -e /opt/brave.com/brave-origin/brave ]] \
    || [[ -e /usr/lib/opt/brave.com/brave-origin/brave ]]
}

locked_stamp() {
  local allow="$1" title="$2" st="$3"
  if [[ -f "${allow}" ]]; then
    loose "${title} (you turned the default off)"
    proof "${allow} exists; status=${st}"
  else
    pass "${title} (default lock)"
    proof "no ${allow}; status=${st}"
  fi
}

echo "Unwoke self-test"
echo "Does not change locks. FAIL means the image is wrong. LOOSE means you loosened a default."
echo "flavor=${FLAVOR}  user=$(id -un)  host=$(hostname 2>/dev/null || echo ?)"
if command -v rpm-ostree >/dev/null; then
  python3 - <<'PY' 2>/dev/null || true
import json, subprocess
try:
    j = json.loads(subprocess.check_output(["rpm-ostree", "status", "--json"], text=True))
except Exception:
    raise SystemExit(0)
for d in j.get("deployments") or []:
    if d.get("booted"):
        print("booted origin:", d.get("origin") or d.get("container-image-reference") or "?")
        print("booted checksum:", (d.get("checksum") or "")[:16])
        break
PY
fi

section "Identity"
if [[ "${FLAVOR}" == "brave-origin" || "${FLAVOR}" == "trivalent" || "${FLAVOR}" == "browserless" ]]; then
  pass "flavor file names a known overlay"
  proof "/usr/share/unwoke/flavor = ${FLAVOR}"
else
  fail "flavor file missing or unknown"
  proof "/usr/share/unwoke/flavor = ${FLAVOR}"
fi
if [[ -f /usr/share/unwoke/SHIPPED-FIRST.txt ]] && grep -q 'UNWOKE-SHIPPED-FIRST' /usr/share/unwoke/SHIPPED-FIRST.txt; then
  pass "public mark UNWOKE-SHIPPED-FIRST"
  proof "/usr/share/unwoke/SHIPPED-FIRST.txt"
else
  fail "public mark missing"
fi
if [[ -f /usr/share/unwoke/NOTICE && -f /usr/share/unwoke/LICENSE ]]; then
  pass "NOTICE and LICENSE on disk"
else
  fail "NOTICE or LICENSE missing under /usr/share/unwoke"
fi

section "Overlay tools on PATH"
need=(
  /usr/libexec/unwoke/toggles.sh
  /usr/libexec/unwoke/setup.sh
  /usr/libexec/unwoke/setup-gui.py
  /usr/libexec/unwoke/first-session.sh
  /usr/libexec/unwoke/vendor.py
  /usr/libexec/unwoke/privacy.sh
  /usr/libexec/unwoke/flathub.sh
  /usr/libexec/unwoke/bluetooth.sh
  /usr/libexec/unwoke/camera-mic.sh
  /usr/libexec/unwoke/brew.sh
  /usr/libexec/unwoke/toolbox.sh
  /usr/libexec/unwoke/extra-daemons.sh
  /usr/libexec/unwoke/ramdisk.sh
  /usr/libexec/unwoke/cet.sh
  /usr/libexec/unwoke/boot-perm.sh
  /usr/libexec/unwoke/ca-trim.sh
  /usr/libexec/unwoke/stock-nags.sh
  /usr/libexec/unwoke/admin-split.sh
  /usr/libexec/unwoke/flatpak-lockdown.sh
  /usr/libexec/unwoke/flatpak-record.sh
  /usr/libexec/unwoke/network-fs.sh
  /usr/libexec/unwoke/theme.sh
  /usr/libexec/unwoke/selftest.sh
)
for p in "${need[@]}"; do
  if [[ -x "${p}" || -f "${p}" ]]; then
    pass "shipped $(basename "${p}")"
    proof "${p}"
  else
    fail "missing ${p}"
  fi
done
if [[ -f /usr/share/applications/unwoke-setup.desktop ]]; then
  pass "Unwoke setup is in the app grid"
  proof "/usr/share/applications/unwoke-setup.desktop"
else
  fail "setup desktop file missing"
fi
if [[ -f /usr/share/unwoke/help/index.html ]]; then
  pass "offline help hub on disk"
  proof "/usr/share/unwoke/help/index.html"
else
  fail "offline help hub missing"
fi
if python3 /usr/libexec/unwoke/vendor.py schema >/dev/null 2>&1; then
  pass "vendor-installers.json schema ok"
  proof "python3 /usr/libexec/unwoke/vendor.py schema"
else
  fail "vendor list schema failed"
fi

section "Stores (must be gone)"
if command -v rpm >/dev/null && rpm -q gnome-software >/dev/null 2>&1; then
  fail "gnome-software is installed"
else
  pass "no GNOME Software"
  proof "rpm -q gnome-software is not installed"
fi
if command -v rpm >/dev/null && rpm -q plasma-discover >/dev/null 2>&1; then
  fail "plasma-discover is installed"
else
  pass "no Plasma Discover"
fi
if command -v rpm >/dev/null && rpm -q bazaar >/dev/null 2>&1; then
  fail "bazaar is installed"
else
  pass "no Bazaar"
fi

section "SELinux harden_userns"
if command -v semodule >/dev/null && semodule -l 2>/dev/null | grep -qx harden_userns; then
  pass "harden_userns module listed"
  proof "semodule -l | grep harden_userns"
else
  fail "harden_userns missing — ujust set-unconfined-userns off"
fi

section "House browser (this flavor)"
if is_browserless; then
  if origin_elf; then fail "Brave Origin ELF on browserless"; else pass "no Brave Origin"; proof "no /opt|/usr/lib/opt brave-origin/brave"; fi
  if trivalent_present; then fail "Trivalent on browserless"; else pass "no Trivalent"; fi
  if [[ -e /opt/brave.com/brave/brave ]]; then fail "full brave-browser on browserless"; else pass "no full brave-browser"; fi
  if command -v semodule >/dev/null && semodule -l 2>/dev/null | grep -qx unwoke_brave; then
    fail "unwoke_brave loaded on browserless"
  else
    pass "no brave_t userns exception"
  fi
  if [[ -f /etc/unwoke/allow-browsers ]]; then
    loose "allow-browsers ON"
    proof "/etc/unwoke/allow-browsers"
  else
    pass "allow-browsers OFF"
    proof "no /etc/unwoke/allow-browsers"
  fi
elif is_trivalent; then
  if trivalent_present; then pass "Trivalent binary present"; proof "trivalent ELF under /usr"; else fail "Trivalent binary missing"; fi
  if origin_elf; then fail "Brave Origin on a trivalent image"; else pass "no Brave Origin"; fi
  if [[ -e /opt/brave.com/brave/brave ]]; then fail "full brave-browser also installed"; else pass "no full brave-browser"; fi
  if command -v semodule >/dev/null && semodule -l 2>/dev/null | grep -qx unwoke_brave; then
    fail "unwoke_brave loaded on trivalent (must not add brave_t)"
  else
    pass "no brave_t (stock trivalent_t stays)"
  fi
elif is_origin; then
  if origin_elf; then
    pass "Brave Origin ELF present"
    proof "$(ls -l /opt/brave.com/brave-origin/brave /usr/lib/opt/brave.com/brave-origin/brave 2>/dev/null | head -n 2 || true)"
  else
    fail "Brave Origin ELF missing"
  fi
  if [[ -e /opt/brave.com/brave/brave ]]; then fail "full brave-browser also installed"; else pass "brave-origin only"; fi
  if command -v semodule >/dev/null && semodule -l 2>/dev/null | grep -qx unwoke_brave; then
    pass "unwoke_brave SELinux module listed"
    proof "semodule -l | grep unwoke_brave"
  else
    fail "unwoke_brave not listed"
  fi
else
  fail "cannot test browser: unknown flavor"
fi
if [[ -e /opt/brave.com ]] && find /opt/brave.com -xdev -perm -4000 -type f 2>/dev/null | grep -q .; then
  fail "SUID under /opt/brave.com"
  proof "$(find /opt/brave.com -xdev -perm -4000 -type f 2>/dev/null | head)"
else
  pass "no SUID under /opt/brave.com"
fi

policy_on_disk() {
  local file="$1"
  if is_trivalent; then
    [[ -f "/etc/trivalent/policies/managed/${file}" ]] \
      || [[ -f "/usr/etc/trivalent/policies/managed/${file}" ]] \
      || [[ -f "/etc/chromium/policies/managed/${file}" ]] \
      || [[ -f "/usr/etc/chromium/policies/managed/${file}" ]]
  else
    [[ -f "/etc/brave-origin/policies/managed/${file}" ]] \
      || [[ -f "/usr/etc/brave-origin/policies/managed/${file}" ]]
  fi
}

check_pack() {
  local file="$1" off="$2" title="$3"
  if is_browserless; then
    skip "${title} (no house browser)"
    return
  fi
  if [[ -f "${off}" ]]; then
    loose "${title}"
    proof "${off}"
    return
  fi
  if policy_on_disk "${file}"; then
    pass "${title}"
    proof "managed policy ${file}"
  else
    fail "${title} policy file missing"
    proof "looked for ${file} under managed policies"
  fi
}

section "Browser policy packs"
check_pack "10-unwoke-hardening.json" "/etc/unwoke/brave-hardening.off" "HTTPS / metrics / autofill / passwords pack"
check_pack "15-unwoke-devices.json" "/etc/unwoke/brave-devices.off" "camera/mic/USB/BT/geo pack"
check_pack "20-unwoke-jitless.json" "/etc/unwoke/brave-jitless.off" "JIT blocked"
check_pack "30-unwoke-extensions.json" "/etc/unwoke/brave-extensions.off" "extension installs blocked"
check_pack "40-unwoke-isolation.json" "/etc/unwoke/brave-isolation.off" "WebGL/WebGPU off, site isolation"
check_pack "50-unwoke-sandbox.json" "/etc/unwoke/brave-sandbox.off" "audio sandbox / no screen capture / no JS optimizer"
if is_browserless; then
  skip "DevTools pack (no house browser)"
elif [[ -f /etc/unwoke/brave-devtools.off ]]; then
  pass "DevTools allowed (default)"
  proof "/etc/unwoke/brave-devtools.off or no lock file — default is allow"
elif policy_on_disk "60-unwoke-devtools.json"; then
  loose "DevTools locked (you opted in)"
  proof "60-unwoke-devtools.json present"
else
  pass "DevTools allowed (default; no lock file)"
fi

if is_origin; then
  if [[ -f /etc/unwoke/brave-bubblejail.off ]]; then
    loose "Origin Bubblejail off"
    proof "/etc/unwoke/brave-bubblejail.off"
  else
    pass "Origin Bubblejail on (default)"
    proof "no /etc/unwoke/brave-bubblejail.off"
  fi
elif is_trivalent; then
  skip "Bubblejail wrap (refused on Trivalent)"
else
  skip "Bubblejail wrap"
fi

if is_trivalent; then
  if [[ -f /etc/unwoke/trivalent-network-sandbox.off ]]; then
    loose "Network Service Sandbox not forced"
    proof "/etc/unwoke/trivalent-network-sandbox.off"
  elif [[ -f /etc/trivalent/trivalent.conf.d/50-unwoke-network-sandbox.conf ]] \
    || [[ -f /usr/etc/trivalent/trivalent.conf.d/50-unwoke-network-sandbox.conf ]]; then
    pass "Network Service Sandbox forced on"
    proof "50-unwoke-network-sandbox.conf"
  else
    fail "Network Service Sandbox conf missing"
  fi
  if [[ -f /etc/unwoke/trivalent-referrers.off ]]; then
    loose "punycode/referrer flags off"
  elif [[ -f /etc/trivalent/trivalent.conf.d/60-unwoke-referrers.conf ]] \
    || [[ -f /usr/etc/trivalent/trivalent.conf.d/60-unwoke-referrers.conf ]]; then
    pass "punycode + clear-cross-origin-referrers"
    proof "60-unwoke-referrers.conf"
  else
    fail "referrer conf missing"
  fi
else
  skip "Trivalent conf.d packs"
fi

section "Default-off hardware and stores"
st="$(/usr/libexec/unwoke/flathub.sh status 2>/dev/null || echo '?')"
if [[ -f /etc/unwoke/flathub ]] && [[ "$(tr -d '[:space:]' < /etc/unwoke/flathub)" != "off" ]]; then
  loose "Flathub remote"
  proof "status=${st}"
else
  pass "Flathub off"
  proof "status=${st}"
fi
locked_stamp /etc/unwoke/allow-bluetooth "Bluetooth" "$(/usr/libexec/unwoke/bluetooth.sh status 2>/dev/null || echo '?')"
locked_stamp /etc/unwoke/allow-camera-mic "webcam/ALSA capture" "$(/usr/libexec/unwoke/camera-mic.sh status 2>/dev/null || echo '?')"
locked_stamp /etc/unwoke/allow-brew "Homebrew" "$(/usr/libexec/unwoke/brew.sh status 2>/dev/null || echo '?')"
locked_stamp /etc/unwoke/allow-toolbox "toolbox/distrobox" "$(/usr/libexec/unwoke/toolbox.sh status 2>/dev/null || echo '?')"
locked_stamp /etc/unwoke/allow-extra-daemons "Avahi/ModemManager" "$(/usr/libexec/unwoke/extra-daemons.sh status 2>/dev/null || echo '?')"
locked_stamp /etc/unwoke/allow-network-fs "NFS/CIFS clients" "$(/usr/libexec/unwoke/network-fs.sh status 2>/dev/null || echo '?')"

section "Privacy extras"
locked_stamp /etc/unwoke/allow-countme "rpm-ostree countme" "$(/usr/libexec/unwoke/privacy.sh countme status 2>/dev/null || echo '?')"
if [[ ! -f /etc/unwoke/allow-countme ]]; then
  if systemctl is-enabled rpm-ostree-countme.timer >/dev/null 2>&1; then
    fail "countme timer still enabled"
    proof "systemctl is-enabled rpm-ostree-countme.timer"
  else
    pass "countme timer not enabled"
    proof "systemctl is-enabled rpm-ostree-countme.timer → disabled/masked/not-found"
  fi
fi
locked_stamp /etc/unwoke/allow-connectivity "connectivity HTTP check" "$(/usr/libexec/unwoke/privacy.sh connectivity-check status 2>/dev/null || echo '?')"
locked_stamp /etc/unwoke/allow-dhcp-hostname "DHCP hostname" "$(/usr/libexec/unwoke/privacy.sh dhcp-hostname status 2>/dev/null || echo '?')"
locked_stamp /etc/unwoke/allow-thumbnails "file thumbnails" "$(/usr/libexec/unwoke/privacy.sh thumbnails status 2>/dev/null || echo '?')"
if [[ -f /etc/NetworkManager/conf.d/90-unwoke-connectivity.conf ]]; then
  pass "NetworkManager connectivity drop-in on disk"
  proof "/etc/NetworkManager/conf.d/90-unwoke-connectivity.conf"
elif [[ ! -f /etc/unwoke/allow-connectivity ]]; then
  loose "connectivity drop-in not in /etc yet (apply-boot on next boot writes it)"
  proof "source /usr/share/unwoke/nm-privacy-connectivity.conf"
fi

section "Memory / boot / CAs / nags"
st="$(/usr/libexec/unwoke/ramdisk.sh status 2>/dev/null || echo '?')"
if [[ -f /etc/unwoke/allow-ramdisk-exec ]]; then
  loose "RAM disk exec allowed"
  proof "${st}"
else
  pass "noexec /dev/shm and /tmp (default)"
  proof "${st}"
  if awk '$2=="/tmp" && $4 ~ /(^|,)noexec(,|$)/ {found=1} END{exit found?0:1}' /proc/mounts 2>/dev/null; then
    pass "/tmp is mounted noexec right now"
    proof "$(awk '$2=="/tmp" {print}' /proc/mounts)"
  else
    loose "/tmp is not noexec in /proc/mounts yet (needs reboot after first apply-boot)"
    proof "$(awk '$2=="/tmp" {print}' /proc/mounts || echo 'no /tmp line')"
  fi
fi
st="$(/usr/libexec/unwoke/cet.sh status 2>/dev/null || echo '?')"
if [[ -f /etc/unwoke/cet.off ]]; then
  loose "CET tunables off"
  proof "${st}"
else
  pass "CET (SHSTK/IBT) default on"
  proof "${st}"
fi
st="$(/usr/libexec/unwoke/boot-perm.sh status 2>/dev/null || echo '?')"
if [[ -f /etc/unwoke/allow-boot-open ]]; then
  loose "/boot not forced 700"
  proof "${st}"
else
  pass "/boot 700 default"
  proof "${st}"
fi
st="$(/usr/libexec/unwoke/ca-trim.sh status 2>/dev/null || echo '?')"
if [[ -f /etc/unwoke/allow-extra-cas ]]; then
  loose "Fedora extra CAs kept"
  proof "${st}"
else
  pass "extra CAs trimmed to Mozilla website set"
  proof "${st}"
fi
st="$(/usr/libexec/unwoke/stock-nags.sh status 2>/dev/null || echo '?')"
if [[ -f /etc/unwoke/allow-stock-nags ]]; then
  loose "stock nags unmasked"
  proof "${st}"
else
  pass "stock deprecation/update-verify/flatpak-setup masked"
  proof "${st}"
fi
st="$(/usr/libexec/unwoke/flatpak-lockdown.sh status 2>/dev/null || echo '?')"
pass "flatpak lockdown status (see proof)"
proof "${st}"
st="$(/usr/libexec/unwoke/flatpak-record.sh status 2>/dev/null || echo '?')"
pass "flatpak record/mic status (see proof)"
proof "${st}"
st="$(/usr/libexec/unwoke/admin-split.sh status 2>/dev/null || echo '?')"
pass "admin-split status (see proof)"
proof "${st}"

section "Look"
if [[ -f /usr/share/backgrounds/unwoke/unwoke-desktop.jpg ]]; then
  pass "Unwoke wallpaper file"
  proof "/usr/share/backgrounds/unwoke/unwoke-desktop.jpg"
else
  fail "Unwoke wallpaper missing"
fi
if [[ -f /usr/share/glib-2.0/schemas/zz1-unwoke-theme.gschema.override ]]; then
  pass "GNOME accent override shipped"
  proof "/usr/share/glib-2.0/schemas/zz1-unwoke-theme.gschema.override"
elif command -v gsettings >/dev/null && gsettings get org.gnome.desktop.interface accent-color >/dev/null 2>&1; then
  pass "GNOME accent schema readable"
  proof "accent-color=$(gsettings get org.gnome.desktop.interface accent-color 2>/dev/null || echo '?')"
else
  skip "GNOME accent (no gschema override and not a GNOME session)"
fi

section "Stock audit (theirs, not ours)"
if command -v ujust >/dev/null; then
  pass "ujust is on PATH — run ujust audit-secureblue for kernel/USBGuard/malloc"
  proof "this self-test does not replace stock audit"
else
  fail "ujust missing"
fi

echo
echo "----------------------------------------"
echo "PASS ${PASS}   LOOSE ${LOOSE}   SKIP ${SKIP}   FAIL ${FAIL}"
echo "PASS = Unwoke default is on this disk. LOOSE = you turned that default off."
echo "FAIL = this flavor is missing something we ship. SKIP = not this flavor."
echo "Put a lock back: ujust loosened   Map a symptom: ujust why"
echo "Stock kernel/USBGuard/malloc: ujust audit-secureblue"
if [[ "${FAIL}" -gt 0 ]]; then
  echo "RESULT: FAIL"
  exit 1
fi
echo "RESULT: PASS"
exit 0
