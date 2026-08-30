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
  /usr/libexec/unwoke/nts.sh
  /usr/libexec/unwoke/usbguard-prompt.sh
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
check_pack "60-unwoke-devtools.json" "/etc/unwoke/brave-devtools.off" "DevTools locked"

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
  if awk '$2=="/tmp" && $4 ~ /(^|,)noexec(,|$)/ {found=1} END{exit found?0:1}' /proc/mounts 2>/dev/null \
    && awk '$2=="/dev/shm" && $4 ~ /(^|,)noexec(,|$)/ {found=1} END{exit found?0:1}' /proc/mounts 2>/dev/null; then
    pass "/tmp and /dev/shm are mounted noexec right now"
    proof "$(awk '$2=="/tmp" || $2=="/dev/shm" {print}' /proc/mounts)"
  else
    fail "#697 mounts lack noexec after boot (apply-boot should remount; this is fail-closed)"
    proof "$(awk '$2=="/tmp" || $2=="/dev/shm" {print}' /proc/mounts || echo 'no lines')"
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

section "Shipped first (stock tickets still open when we shipped)"
echo "  Ledger: /usr/share/unwoke/SHIPPED-FIRST.txt"
echo "  Site:   https://sergi270710267.github.io/unwoke-secureblue/ahead/"

# #391 — chmod 700 /boot
if [[ -f /etc/unwoke/allow-boot-open ]]; then
  loose "#391 /boot not forced 700"
  proof "ujust set-boot-perm off; $(stat -c '%a %n' /boot 2>/dev/null || echo 'no /boot')"
else
  mode="$(stat -c '%a' /boot 2>/dev/null || echo '?')"
  if [[ "${mode}" == "700" ]]; then
    pass "#391 /boot is mode 700"
    proof "stat -c %a /boot = ${mode}"
  else
    fail "#391 /boot is ${mode} (want 700; boot-perm.sh apply-boot)"
    proof "stat -c %a /boot = ${mode}"
  fi
  for d in /usr/src /usr/lib/modules; do
    [[ -d "${d}" && ! -L "${d}" ]] || continue
    m="$(stat -c '%a' "${d}" 2>/dev/null || echo '?')"
    if [[ "${m}" == "700" ]]; then
      pass "#391 ${d} is mode 700 (compose)"
      proof "stat -c %a ${d} = ${m}"
    else
      fail "#391 ${d} is ${m} (want 700 at compose)"
      proof "stat -c %a ${d} = ${m}"
    fi
  done
fi

# #697 — noexec RAM disks
shm="$(awk '$2=="/dev/shm" {print}' /proc/mounts 2>/dev/null || true)"
tmpm="$(awk '$2=="/tmp" {print}' /proc/mounts 2>/dev/null || true)"
if [[ -f /etc/unwoke/allow-ramdisk-exec ]]; then
  loose "#697 RAM-disk exec allowed"
  proof "/etc/unwoke/allow-ramdisk-exec"
else
  if awk '$2=="/dev/shm" && $4 ~ /(^|,)noexec(,|$)/ {ok=1} END{exit ok?0:1}' /proc/mounts \
    && awk '$2=="/tmp" && $4 ~ /(^|,)noexec(,|$)/ {ok=1} END{exit ok?0:1}' /proc/mounts; then
    pass "#697 /dev/shm and /tmp mounted noexec,nosuid,nodev"
    proof "/dev/shm: ${shm}"
    proof "/tmp: ${tmpm}"
  else
    fail "#697 mounts lack noexec (fail-closed; first-boot apply-boot should remount)"
    proof "/dev/shm: ${shm:-missing} | /tmp: ${tmpm:-missing}"
  fi
fi

# #887 — Flatpak session/system bus in overlay audit
fp_over="$( { command -v flatpak >/dev/null && { flatpak override --show; echo; flatpak override --user --show; }; } 2>/dev/null || true )"
if ! command -v flatpak >/dev/null; then
  skip "#887 Flatpak not installed (cannot show overrides)"
elif [[ -f /etc/unwoke/flatpak-lockdown.off ]]; then
  loose "#887 lockdown off — session-bus check is hygiene on a loosened image"
  proof "/etc/unwoke/flatpak-lockdown.off"
else
  bus_hit=0
  if printf '%s\n' "${fp_over}" | grep -E '(^|;)session-bus(;|$)' | grep -vq '!session-bus'; then
    fail "#887 Flatpak session-bus is allowed"
    proof "$(printf '%s\n' "${fp_over}" | grep -E 'session-bus' | head)"
    bus_hit=1
  fi
  if printf '%s\n' "${fp_over}" | grep -E '(^|;)system-bus(;|$)' | grep -vq '!system-bus'; then
    fail "#887 Flatpak system-bus is allowed"
    proof "$(printf '%s\n' "${fp_over}" | grep -E 'system-bus' | head)"
    bus_hit=1
  fi
  if printf '%s\n' "${fp_over}" | grep -q 'org.freedesktop.Flatpak' \
    && ! printf '%s\n' "${fp_over}" | grep -q '!org.freedesktop.Flatpak'; then
    fail "#887 Flatpak talk-name org.freedesktop.Flatpak present"
    bus_hit=1
  fi
  if [[ "${bus_hit}" -eq 0 ]]; then
    pass "#887 Flatpak session-bus / system-bus / org.freedesktop.Flatpak not allowed"
    proof "flatpak override --show does not grant those (stock audit-secureblue still does not warn)"
  fi
fi

# #1185 — NTS on live ISO and installed OS
if [[ -f /etc/unwoke/allow-clear-ntp ]]; then
  loose "#1185 chrony NTS drop-in off"
  proof "/etc/unwoke/allow-clear-ntp"
elif [[ -f /etc/chrony.d/50-unwoke-nts.conf ]] \
  && grep -q 'nts' /etc/chrony.d/50-unwoke-nts.conf \
  && grep -q 'time.cloudflare.com' /etc/chrony.d/50-unwoke-nts.conf; then
  pass "#1185 chrony uses NTS (Cloudflare + nts.ntp.se)"
  proof "$(grep -E '^server' /etc/chrony.d/50-unwoke-nts.conf | tr '\n' '; ')"
else
  fail "#1185 NTS drop-in missing (fail-closed; nts.sh apply-boot)"
  proof "looked at /etc/chrony.d/50-unwoke-nts.conf"
fi

# #1295 — CET
if [[ -f /etc/unwoke/cet.off ]]; then
  loose "#1295 CET tunables off"
  proof "/etc/unwoke/cet.off"
else
  cetf=""
  [[ -f /etc/systemd/system.conf.d/90-unwoke-cet.conf ]] && cetf="/etc/systemd/system.conf.d/90-unwoke-cet.conf"
  [[ -z "${cetf}" && -f /usr/share/unwoke/cet-system.conf ]] && cetf="/usr/share/unwoke/cet-system.conf"
  if [[ -n "${cetf}" ]] && grep -q 'x86_shstk=on' "${cetf}" && grep -q 'x86_ibt=on' "${cetf}"; then
    pass "#1295 glibc SHSTK+IBT tunables shipped on"
    proof "${cetf}: $(grep DefaultEnvironment "${cetf}" | head -n 1)"
  else
    fail "#1295 CET drop-in missing SHSTK/IBT"
    proof "looked at ${cetf:-none}"
  fi
fi

# #1569 — DHCP anonymization
dhcpf=""
[[ -f /etc/NetworkManager/conf.d/90-unwoke-dhcp.conf ]] && dhcpf="/etc/NetworkManager/conf.d/90-unwoke-dhcp.conf"
[[ -z "${dhcpf}" && -f /usr/share/unwoke/nm-privacy-dhcp.conf ]] && dhcpf="/usr/share/unwoke/nm-privacy-dhcp.conf"
if [[ -f /etc/unwoke/allow-dhcp-hostname ]]; then
  loose "#1569 DHCP hostname/IDs loosened"
  proof "/etc/unwoke/allow-dhcp-hostname"
elif [[ -n "${dhcpf}" ]] \
  && grep -q 'dhcp-send-release=true' "${dhcpf}" \
  && grep -q 'dhcp-iaid=mac' "${dhcpf}" \
  && grep -q 'dhcp-send-hostname=false' "${dhcpf}"; then
  pass "#1569 DHCP anonymization (no hostname, iaid=mac, send-release)"
  proof "${dhcpf}"
else
  fail "#1569 DHCP anonymization keys missing"
  proof "file=${dhcpf:-none}"
fi

# #1606 — CA trim
if [[ -f /etc/unwoke/allow-extra-cas ]]; then
  loose "#1606 extra Fedora CAs allowed"
  proof "/etc/unwoke/allow-extra-cas"
else
  nblock="$(find /etc/pki/ca-trust/source/blocklist -name 'unwoke-*.pem' 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "${nblock}" -gt 0 ]]; then
    pass "#1606 Fedora-not-Mozilla CAs blocklisted (${nblock} pems)"
    proof "/etc/pki/ca-trust/source/blocklist/unwoke-*.pem"
  else
    fail "#1606 CA blocklist not live (fail-closed; apply-boot should copy pems)"
    proof "source=/usr/share/unwoke/ca-blocklist dest=/etc/pki/ca-trust/source/blocklist"
  fi
fi

# #1885 — extra Flatpak filesystem cuts
if ! command -v flatpak >/dev/null; then
  skip "#1885 Flatpak not installed"
elif [[ -f /etc/unwoke/flatpak-lockdown.off ]]; then
  loose "#1885 extra xdg/host-root cuts off with lockdown"
  proof "/etc/unwoke/flatpak-lockdown.off"
else
  if printf '%s\n' "${fp_over}" | grep -q 'host-root' && printf '%s\n' "${fp_over}" | grep -q 'xdg-download'; then
    pass "#1885 Flatpak extra xdg + host-root cuts present"
    proof "$(printf '%s\n' "${fp_over}" | grep -E 'host-root|xdg-download' | head -n 4)"
  else
    loose "#1885 extra FS cuts not visible in override --show yet (apply-boot)"
    proof "lockdown script extra_fs includes host-root and xdg-*"
  fi
fi

# #2156 — Flatpak record streams
if ! command -v flatpak >/dev/null; then
  skip "#2156 Flatpak not installed"
elif [[ -f /etc/unwoke/flatpak-record.off ]]; then
  loose "#2156 Flatpak Pulse/PipeWire record allowed"
  proof "/etc/unwoke/flatpak-record.off"
else
  if printf '%s\n' "${fp_over}" | grep -Eqi 'pulseaudio|pipewire'; then
    pass "#2156 Flatpak record path mentioned in overrides"
    proof "$(printf '%s\n' "${fp_over}" | grep -Ei 'pulseaudio|pipewire' | head -n 4)"
  else
    loose "#2156 record-block not visible in override --show yet (apply-boot)"
    proof "flatpak-record.sh --nosocket=pulseaudio --nofilesystem=xdg-run/pipewire-0"
  fi
fi

# #2354 — network fs clients
if [[ -f /etc/unwoke/allow-network-fs ]]; then
  loose "#2354 NFS/CIFS clients allowed"
  proof "/etc/unwoke/allow-network-fs"
else
  nfsf=""
  [[ -f /etc/modprobe.d/unwoke-network-fs.conf ]] && nfsf="/etc/modprobe.d/unwoke-network-fs.conf"
  [[ -z "${nfsf}" && -f /usr/share/unwoke/modprobe-network-fs.conf ]] && nfsf="/usr/share/unwoke/modprobe-network-fs.conf"
  if [[ -n "${nfsf}" ]] && grep -q 'blacklist nfs' "${nfsf}" && grep -q 'blacklist cifs' "${nfsf}"; then
    pass "#2354 NFS/CIFS client modules blacklisted"
    proof "${nfsf}"
  else
    fail "#2354 network-fs blacklist missing"
  fi
fi

# #2432 — Anaconda encrypt default (live ISO)
if grep -Rqs 'autopart --encrypted' /etc/anaconda /usr/share/anaconda 2>/dev/null \
  || grep -qs 'autopart --encrypted' /etc/anaconda/profile.d/*.conf 2>/dev/null; then
  pass "#2432 Anaconda autopart is encrypted by default"
  proof "$(grep -R 'autopart --encrypted' /etc/anaconda /usr/share/anaconda 2>/dev/null | head -n 2)"
else
  skip "#2432 LUKS opt-out is live-ISO Anaconda (not on an installed ostree)"
  proof "prep_rootfs.sh writes autopart --encrypted on the USB only"
fi

# #2508 — Flatpak web browsers
if ! command -v flatpak >/dev/null; then
  skip "#2508 Flatpak not installed"
else
  apps="$(flatpak list --app --columns=application 2>/dev/null || true)"
  hit=""
  while IFS= read -r br; do
    [[ -n "${br}" ]] || continue
    case "${br}" in
      org.mozilla.firefox*|com.google.Chrome*|com.brave.Browser*|com.microsoft.Edge*|org.chromium.Chromium*|io.github.ungoogled*|net.mullvad.MullvadBrowser*|org.torproject.*|io.gitlab.librewolf*|app.zen_browser.*|org.gnome.Epiphany*|com.vivaldi.*|com.opera.Opera*)
        hit="${hit} ${br}"
        ;;
    esac
  done <<<"${apps}"
  if [[ -n "${hit}" ]]; then
    if is_browserless; then
      fail "#2508 browserless image has Flatpak web browser(s):${hit}"
    else
      loose "#2508 Flatpak web browser installed:${hit} (hygiene; stock audit-secureblue does not report this)"
    fi
    proof "flatpak list --app"
  else
    pass "#2508 no Flatpak web browser installed"
    proof "flatpak list --app has none of the known browser IDs"
  fi
fi

# USBGuard: prompt once, never silent
if [[ -f /etc/usbguard/rules.conf ]] && grep -q '[^[:space:]]' /etc/usbguard/rules.conf 2>/dev/null; then
  pass "USBGuard rules file is non-empty"
  proof "/etc/usbguard/rules.conf"
elif [[ -f /etc/unwoke/usbguard-prompt.done ]]; then
  loose "USBGuard first-boot prompt skipped (you chose No). Later: ujust setup-usbguard"
  proof "/etc/unwoke/usbguard-prompt.done"
else
  skip "USBGuard prompt not run yet (tty1 first boot)"
  proof "service unwoke-usbguard-prompt.service"
fi

# #2526 — LUKS argon2id 2 GiB
cs=""
[[ -f /etc/cryptsetup.conf ]] && cs="/etc/cryptsetup.conf"
[[ -z "${cs}" && -f /usr/etc/cryptsetup.conf ]] && cs="/usr/etc/cryptsetup.conf"
if [[ -n "${cs}" ]] && grep -q 'argon2id' "${cs}" && grep -q '2097152' "${cs}"; then
  pass "#2526 cryptsetup default Argon2id memory 2 GiB"
  proof "${cs}: $(grep -E 'pbkdf' "${cs}" | tr '\n' ' ')"
else
  fail "#2526 cryptsetup Argon2id 2 GiB conf missing"
  proof "looked at /etc/cryptsetup.conf and /usr/etc/cryptsetup.conf"
fi

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
echo "FAIL = this flavor is missing something we ship. SKIP = not this flavor / live-ISO-only."
echo "Shipped-first tickets (#391 #697 #887 #1185 #1295 #1569 #1606 #1885 #2156 #2354 #2432 #2508 #2526) have their own proof lines."
echo "Put a lock back: ujust loosened   Map a symptom: ujust why"
echo "Stock kernel/USBGuard/malloc: ujust audit-secureblue"
if [[ "${FAIL}" -gt 0 ]]; then
  echo "RESULT: FAIL"
  exit 1
fi
echo "RESULT: PASS"
exit 0
