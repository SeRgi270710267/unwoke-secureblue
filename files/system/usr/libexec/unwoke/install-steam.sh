#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Wrap stock ujust install-steam. Steam is Flathub com.valvesoftware.Steam
# (not verified). Overlay locks that stop it working like stock are asked.
# Nothing auto-unlocks. Do not call stock set-flathub-unfiltered (fights our stamp).
set -euo pipefail

TOGGLES="/usr/libexec/unwoke/toggles.sh"
APP_ID="com.valvesoftware.Steam"

ask() {
  local prompt="$1" def="${2:-N}"
  local ans=""
  read -r -p "${prompt} [${def}] " ans || true
  ans="${ans:-$def}"
  [[ "${ans}" == [yY] ]]
}

run_toggle() {
  [[ -x "${TOGGLES}" ]] || { echo "missing ${TOGGLES}" >&2; return 1; }
  "${TOGGLES}" "$@" || echo "That toggle did not finish. Locks unchanged if it aborted."
}

grant_steam() {
  command -v flatpak >/dev/null || return 0
  # Per-app only. Global lockdown / record stay on for every other Flatpak.
  local cmd=(flatpak override --user "${APP_ID}")
  "${cmd[@]}" --share=network --share=ipc \
    --socket=wayland --socket=fallback-x11 --socket=pulseaudio \
    --device=dri --device=input --device=shm \
    --allow=multiarch \
    --filesystem=home --filesystem=xdg-download \
    --filesystem=/run/media --filesystem=/var/mnt \
    --filesystem=xdg-run/pipewire-0 \
    --talk-name=com.feralinteractive.GameMode || true
  echo "Per-app grants on ${APP_ID} (user override). Other Flatpaks keep overlay lockdown."
}

echo
echo "=== Steam (stock path: unfiltered Flathub Flatpak) ==="
echo "Stock: ujust install-steam turns on unfiltered Flathub and installs"
echo "${APP_ID}, then asks about Xwayland. Anti-cheat is leftover stock:"
echo "  ujust set-anticheat-support"
echo
echo "Unwoke extras that stop Steam working as well as on stock:"
echo "  - Flathub is OFF. Steam is not in the verified subset — need full."
echo "  - Flatpak lockdown is ON (stock: opt-in). Steam needs net, library, GPU, pads, audio."
echo "  - Flatpak record lock also cuts Pulse for Flatpaks (silent games / no Steam Voice)."
echo "  - /tmp /dev/shm /var/tmp noexec (stock does not). Proton/Wine often exec from temp."
echo "  - Camera/mic kernel lock → Steam Voice hardware."
echo "  - Bluetooth service masked → wireless controllers."
echo "Xwayland and 32-bit kargs are the same as stock (asked, not silent)."
echo "Stock also offers Distrobox steambox (SteamVR). That needs toolbox wrappers on."
echo "Nothing is flipped unless you say yes."
echo
echo "  1) Flatpak (unfiltered Flathub) — recommended"
echo "  2) Distrobox steambox (bazzite-arch) — SteamVR"
read -r -p "Selection [1]: " method || true
method="${method:-1}"
if [[ "${method}" == "2" ]]; then
  if ! ask "Turn toolbox/distrobox wrappers on (required)?" "y"; then
    echo "Aborted. Later: ujust set-toolbox on && ujust install-steam"
    exit 0
  fi
  run_toggle toolbox on
  if ask "Allow container-domain userns (stock leftover; Distrobox needs it)?" "y"; then
    ujust set-container-userns on || true
  fi
  if ask "Enable Xwayland (Steam still wants it)?" "n"; then
    ujust set-xwayland on || true
  fi
  echo "Creating steambox (stock image ghcr.io/ublue-os/steambox)."
  distrobox-create --unshare-netns --nvidia --image ghcr.io/ublue-os/steambox --name steambox -Y || {
    echo "distrobox-create failed. Is the wrapper on? ujust set-toolbox on"
    exit 1
  }
  distrobox-enter -n steambox -- distrobox-export --app steam || true
  echo "Anti-cheat: ujust set-anticheat-support (leftover stock)."
  exit 0
fi

if ! ask "Enable unfiltered Flathub (full) so Steam can be installed? Required." "y"; then
  echo "Aborted. Steam is not on verified Flathub. Later: ujust set-flathub full && ujust install-steam"
  exit 0
fi
run_toggle flathub full

if ask "Grant THIS Steam Flatpak net/home/GPU/pads/audio (keep lockdown on other apps)?" "y"; then
  : # grants after install so the app exists
  GRANT=1
else
  GRANT=0
  echo "Steam will likely fail until Flatseal grants or: ujust set-flatpak-lockdown off"
fi

if ask "Turn overlay Flatpak lockdown OFF for every Flatpak (wider than Steam)?" "n"; then
  run_toggle lockdown off
fi

if ask "Allow Flatpak Pulse/PipeWire record globally (Steam Voice + other Flatpaks)?" "n"; then
  run_toggle flatpak-record off
fi

if ask "Allow exec on /tmp /dev/shm /var/tmp (Proton/Wine; revert: ujust set-ramdisk-exec off)?" "n"; then
  run_toggle ramdisk-exec on
fi

if ask "Turn camera/mic hardware on (Steam Voice; speakers already work)?" "n"; then
  run_toggle camera-mic on
fi

if ask "Turn Bluetooth on (wireless controllers; Wi-Fi already on)?" "n"; then
  run_toggle bluetooth on
fi

echo
echo "Installing ${APP_ID} from Flathub..."
if ! command -v flatpak >/dev/null; then
  echo "FAIL: flatpak not installed" >&2
  exit 1
fi
flatpak install -y flathub "${APP_ID}"

if [[ "${GRANT}" -eq 1 ]]; then
  grant_steam
fi

echo
echo "Stock leftover (same as their FAQ; we do not silent-enable):"
if ask "Enable Xwayland (many games still need it; stock also asks)?" "n"; then
  if command -v ujust >/dev/null; then
    ujust set-xwayland on || echo "set-xwayland failed; run it later"
  fi
fi
echo "32-bit games: ujust --choose  →  kargs-32bit (same as stock)."
echo "Anti-cheat / mods needing ptrace: ujust set-anticheat-support (leftover stock)."
echo "USBGuard blocking a dongle: Unwoke setup → leftover stock, or ujust setup-usbguard."
echo
echo "Put locks back: ujust setup → You loosened, or:"
echo "  ujust set-flathub off"
echo "  ujust set-flatpak-lockdown on"
echo "  ujust set-flatpak-record on"
echo "  ujust set-ramdisk-exec off"
echo "  ujust set-camera-mic off"
echo "  ujust set-bluetooth off"
echo "Play window (GameMode, restores locks when Steam exits): ujust play steam"
echo "Tutorial: ujust setup, or https://sergi270710267.github.io/unwoke-secureblue/tutorials/steam/"
if [[ -x /usr/libexec/unwoke/open-tutorial.sh ]]; then
  bash /usr/libexec/unwoke/open-tutorial.sh steam || true
fi
