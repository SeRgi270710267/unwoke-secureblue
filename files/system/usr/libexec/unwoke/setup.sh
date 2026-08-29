#!/usr/bin/env bash
# First-session / ujust setup. Defaults stay locked unless the user turns one off.
set -euo pipefail

TOGGLES="/usr/libexec/unwoke/toggles.sh"
SEEN="${XDG_CONFIG_HOME:-$HOME/.config}/unwoke/setup-seen"
STAGED="/etc/unwoke/signed-staged"
FLAVOR="unknown"
if [[ -f /usr/share/unwoke/flavor ]]; then
  FLAVOR="$(tr -d '[:space:]' < /usr/share/unwoke/flavor)"
fi

jump=""
case "${1:-}" in
  --broken|broken|why) jump="broken" ;;
  --stock|stock) jump="stock" ;;
  --hardware|hardware) jump="hardware" ;;
  --loosened|loosened) jump="loosened" ;;
  --proton|proton) jump="proton" ;;
  --ivpn|ivpn) jump="ivpn" ;;
  --vendors|vendors) jump="vendors" ;;
  "" ) ;;
  *)
    echo "usage: setup.sh [--broken|--stock|--hardware|--loosened|--proton|--ivpn]" >&2
    exit 2
    ;;
esac

need_toggles() {
  [[ -x "${TOGGLES}" ]] || { echo "missing ${TOGGLES}" >&2; exit 1; }
}

mark_seen() {
  mkdir -p "$(dirname "${SEEN}")"
  date -u +%Y-%m-%dT%H:%M:%SZ > "${SEEN}"
}

reboot_now() {
  if command -v systemctl >/dev/null; then
    systemctl reboot
  else
    reboot
  fi
}

run_toggle() {
  need_toggles
  "${TOGGLES}" "$@" || echo "That toggle did not finish. Locks are unchanged if it aborted."
}

TUTORIALS="https://sergi270710267.github.io/unwoke-secureblue/tutorials"
open_tutorial() {
  local slug="${1:-}"
  echo "Tutorial: ${TUTORIALS}/${slug}/"
  read -r -p "Open in browser? [y/N] " ans || return 0
  [[ "${ans}" == [yY] ]] || return 0
  bash /usr/libexec/unwoke/open-tutorial.sh "${slug}" || true
}

run_stock() {
  local recipe="$1"
  shift
  echo
  printf '%s\n' "$@"
  echo "Command: ujust ${recipe}"
  if ! command -v ujust >/dev/null; then
    echo "ujust is not on PATH. Run that later in a terminal."
    return 0
  fi
  read -r -p "Run it now? [y/N] " ans || return 0
  [[ "${ans}" == [yY] ]] || return 0
  # Nested ujust is fine; these are stock recipes, not overlay locks.
  ujust "${recipe}" || echo "that command failed; you can retry later"
}

header() {
  echo
  echo "Unwoke SecureBlue setup"
  echo "Locks stay on unless you turn one off."
  echo "Flavor: ${FLAVOR}"
  if [[ -f "${STAGED}" ]]; then
    echo
    echo "A signed update is staged. Reboot once to lock updates to our key."
  fi
  echo
}

menu() {
  cat <<'EOF'
  1) Keep all defaults (recommended)
  2) Turn something on (you pick; nothing is auto-unlocked)
  3) Something seems broken (lock, not a bug)
  4) Leftover stock steps (Secure Boot, kargs, USBGuard)
  5) Create a daily (non-wheel) user
  6) You turned something off (put it back)
  7) Proton.me apps (web first; hashed RPM only if you insist)
  8) IVPN (WireGuard first; official repo only if you insist)
  9) All strict apps (every vendor in the watched list)
  s) Show status
  r) Reboot now
  n) Do not show this on login again
  q) Quit
EOF
}

hardware_menu() {
  echo
  echo "Turn something on. Each line is optional. Defaults stay locked."
  cat <<'EOF'
  1) Flathub: verified apps
  2) Bluetooth on (Wi-Fi is already on)
  3) Camera / microphone on
  4) Toolbox / distrobox on
  5) Homebrew on
  6) Avahi (.local) / ModemManager on
EOF
  if [[ "${FLAVOR}" == "browserless" ]]; then
    echo "  7) Allow host browsers (you still type ALLOW)"
  fi
  echo "  b) Back"
}

broken_menu() {
  echo
  echo "These look like bugs. They are default locks. Nothing turns off until you pick it."
  cat <<'EOF'
  1) Websites broken (JavaScript JIT)
  2) Need camera / mic / USB in the browser
  3) Need passwords / autofill
  4) Need extensions
  5) WebGL / WebGPU / 3D sites
  6) Flatpaks do nothing
  7) Screen capture / JS optimizer
  8) Wheel cannot log into GNOME/KDE
EOF
  case "${FLAVOR}" in
    brave-origin)
      echo "  9) Origin window / GPU / audio dead (Bubblejail)"
      ;;
    trivalent)
      echo "  9) Trivalent clears cookies on exit (Network Service Sandbox)"
      ;;
    browserless)
      echo "  9) Cannot install a browser"
      ;;
  esac
  echo "  0) No software store (by design; Flathub is off)"
  echo "  b) Back"
}

stock_menu() {
  echo
  echo "Their post-install, not ours. Overlay locks are unchanged."
  echo "Full text: https://sergi270710267.github.io/unwoke-secureblue/secureblue/post-install/"
  cat <<'EOF'
  1) Enroll their Secure Boot key (prompt password: secureblue)
  2) Apply hardening kernel arguments (needed after a rebase)
  3) USBGuard: allow current USB devices, block the rest
  4) audit-secureblue
  5) Open BIOS/UEFI (ujust bios)
  b) Back
EOF
}

hardware_loop() {
  while true; do
    hardware_menu
    echo
    read -r -p "Choice: " ans || return 0
    case "${ans}" in
      1) run_toggle flathub verified; open_tutorial install-apps ;;
      2) run_toggle bluetooth on; open_tutorial bluetooth ;;
      3) run_toggle camera-mic on; open_tutorial camera-mic ;;
      4) run_toggle toolbox on; open_tutorial toolbox ;;
      5) run_toggle brew on; open_tutorial install-apps ;;
      6) run_toggle extra-daemons on ;;
      7)
        if [[ "${FLAVOR}" == "browserless" ]]; then
          echo "Next prompt: type ALLOW to unlock easy host browsers."
          run_toggle allow-browsers on
        else
          echo "That option is browserless-only."
        fi
        ;;
      b|B|q|Q|"") return 0 ;;
      *) echo "Unknown choice." ;;
    esac
    echo
  done
}

broken_loop() {
  while true; do
    broken_menu
    echo
    read -r -p "Choice: " ans || return 0
    case "${ans}" in
      1)
        run_toggle jitless off
        echo "Restart the house browser."
        open_tutorial sites-broken
        ;;
      2)
        run_toggle devices off
        echo "If the webcam is still dead at the kernel: turn camera/mic on from menu 2."
        echo "Restart the house browser."
        open_tutorial camera-mic
        ;;
      3)
        run_toggle hardening off
        echo "Restart the house browser."
        open_tutorial sites-broken
        ;;
      4)
        run_toggle extensions allow
        echo "Restart the house browser."
        open_tutorial sites-broken
        ;;
      5)
        run_toggle isolation off
        echo "Restart the house browser."
        open_tutorial sites-broken
        ;;
      6)
        run_toggle lockdown off
        open_tutorial install-apps
        ;;
      7)
        run_toggle sandbox off
        echo "Restart the house browser."
        open_tutorial screen-share
        ;;
      8)
        run_toggle admin-split off
        echo "Wheel can use the greeter again. TTY and run0 always worked."
        open_tutorial daily-user
        ;;
      9)
        case "${FLAVOR}" in
          brave-origin)
            run_toggle bubblejail off
            echo "Restart Brave Origin."
            ;;
          trivalent)
            run_toggle network-sandbox off
            echo "Restart Trivalent."
            ;;
          browserless)
            echo "Next prompt: type ALLOW to unlock easy host browsers."
            run_toggle allow-browsers on
            ;;
          *)
            echo "No flavor-specific lock for 9."
            ;;
        esac
        ;;
      0)
        echo "There is no GUI store on purpose (Bazaar / GNOME Software / Discover are gone)."
        echo "Flathub is off until you turn it on. Menu 2 → Flathub: verified apps."
        echo "That is not a crash."
        ;;
      b|B|q|Q|"") return 0 ;;
      *) echo "Unknown choice." ;;
    esac
    echo
  done
}

stock_loop() {
  while true; do
    stock_menu
    echo
    read -r -p "Choice: " ans || return 0
    case "${ans}" in
      1)
        run_stock enroll-secureblue-secure-boot-key \
          "Enroll the secureblue Secure Boot key. BIOS prompt password is: secureblue"
        ;;
      2)
        run_stock set-kargs-hardening \
          "Apply their hardening kernel arguments. Needed if you rebased instead of using their ISO."
        ;;
      3)
        run_stock setup-usbguard \
          "USBGuard: generate a policy from currently attached USB devices and block others."
        open_tutorial usb
        ;;
      4)
        run_stock audit-secureblue \
          "Stock audit. Overlay audit is: ujust audit-unwoke"
        ;;
      5)
        run_stock bios \
          "Reboot into BIOS/UEFI. Use this to disable USB boot if you want that."
        ;;
      b|B|q|Q|"") return 0 ;;
      *) echo "Unknown choice." ;;
    esac
    echo
  done
}

loosened_loop() {
  echo
  echo "Defaults are locked. Only what you turned off is listed."
  local n=0
  declare -a keys=()
  declare -a restores=()
  declare -a slugs=()
  add_item() {
    local title="$1" restore="$2" slug="$3"
    n=$((n + 1))
    keys+=("${title}")
    restores+=("${restore}")
    slugs+=("${slug}")
    echo "  ${n}) ${title}  — put it back"
  }
  [[ -f /etc/unwoke/allow-bluetooth ]] && add_item "Bluetooth" "bluetooth off" "bluetooth"
  if [[ -f /etc/unwoke/flathub ]]; then
    local st
    st="$(tr -d '[:space:]' < /etc/unwoke/flathub)"
    [[ "${st}" != "off" && -n "${st}" ]] && add_item "Flathub" "flathub off" "install-apps"
  fi
  [[ -f /etc/unwoke/allow-brew ]] && add_item "Homebrew" "brew off" "install-apps"
  [[ -f /etc/unwoke/allow-toolbox ]] && add_item "Toolbox" "toolbox off" "toolbox"
  [[ -f /etc/unwoke/allow-camera-mic ]] && add_item "Camera / mic" "camera-mic off" "camera-mic"
  [[ -f /etc/unwoke/allow-extra-daemons ]] && add_item "Avahi / ModemManager" "extra-daemons off" "first-hour"
  [[ -f /etc/unwoke/flatpak-lockdown.off ]] && add_item "Flatpak lockdown off" "lockdown on" "install-apps"
  [[ -f /etc/unwoke/brave-jitless.off ]] && add_item "JavaScript JIT allowed" "jitless on" "sites-broken"
  [[ -f /etc/unwoke/brave-devices.off ]] && add_item "Browser devices allowed" "devices on" "camera-mic"
  [[ -f /etc/unwoke/brave-hardening.off ]] && add_item "Hardening pack off" "hardening on" "sites-broken"
  [[ -f /etc/unwoke/brave-extensions.off ]] && add_item "Extensions allowed" "extensions block" "sites-broken"
  [[ -f /etc/unwoke/brave-isolation.off ]] && add_item "WebGL allowed" "isolation on" "sites-broken"
  [[ -f /etc/unwoke/brave-sandbox.off ]] && add_item "Screen capture pack off" "sandbox on" "screen-share"
  [[ -f /etc/unwoke/brave-bubblejail.off ]] && add_item "Origin Bubblejail off" "bubblejail on" "sites-broken"
  [[ -f /etc/unwoke/trivalent-network-sandbox.off ]] && add_item "Trivalent network sandbox off" "network-sandbox on" "sites-broken"
  [[ -f /etc/unwoke/admin-split.off ]] && add_item "Admin split off" "admin-split on" "daily-user"
  [[ -f /etc/unwoke/allow-browsers ]] && add_item "Host browsers allowed" "allow-browsers off" "install-apps"
  if [[ "${n}" -eq 0 ]]; then
    echo "Nothing loosened. Defaults are on."
    return 0
  fi
  echo "  b) Back"
  echo
  read -r -p "Choice: " ans || return 0
  case "${ans}" in
    b|B|q|Q|"") return 0 ;;
  esac
  [[ "${ans}" =~ ^[0-9]+$ ]] || { echo "Unknown choice."; return 0; }
  local i=$((ans - 1))
  [[ "${i}" -ge 0 && "${i}" -lt "${n}" ]] || { echo "Unknown choice."; return 0; }
  # shellcheck disable=SC2086
  run_toggle ${restores[$i]}
  open_tutorial "${slugs[$i]}"
}

create_daily() {
  echo
  echo "Creates a non-wheel daily user. Wheel stays for TTY/run0."
  echo "Graphical login is then blocked for wheel once that user exists."
  read -r -p "Daily username (empty cancels): " name || return 0
  [[ -n "${name}" ]] || { echo "skipped"; return 0; }
  run_toggle admin-split add "${name}"
}

loop() {
  header
  case "${jump}" in
    broken) broken_loop ;;
    stock) stock_loop ;;
    hardware) hardware_loop ;;
    loosened) loosened_loop ;;
    proton) bash /usr/libexec/unwoke/install-proton.sh ;;
    ivpn) bash /usr/libexec/unwoke/install-ivpn.sh ;;
    vendors) bash /usr/libexec/unwoke/install-vendor.sh ;;
  esac
  while true; do
    menu
    echo
    read -r -p "Choice: " ans || exit 0
    case "${ans}" in
      1)
        mark_seen
        echo "Defaults kept. Later: ujust setup   (broken: ujust why)"
        return 0
        ;;
      2) hardware_loop ;;
      3) broken_loop ;;
      4) stock_loop ;;
      5) create_daily ;;
      6) loosened_loop ;;
      7) bash /usr/libexec/unwoke/install-proton.sh ;;
      8) bash /usr/libexec/unwoke/install-ivpn.sh ;;
      9) bash /usr/libexec/unwoke/install-vendor.sh ;;
      s|S) run_toggle status ;;
      r|R)
        echo "Rebooting."
        reboot_now
        ;;
      n|N)
        mark_seen
        echo "Won't open on login. Run: ujust setup   (broken: ujust why)"
        return 0
        ;;
      q|Q|"") return 0 ;;
      *) echo "Unknown choice." ;;
    esac
    echo
  done
}

loop
