# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Overlay extras. All stock secureblue ujust commands still exist.
# Browser policy commands apply on Origin and -trivalent, not -browserless.
# Every overlay hardening switch has on/off/status (or an equivalent revert).

# First-session menu. Defaults stay locked unless you turn one off.
setup:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/first-session.sh --force

unwoke-setup:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/first-session.sh --force

# Jump to "something seems broken". Does not auto-unlock.
why:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/first-session.sh --force --broken

# Locks you turned off, with put-back. Does not auto-unlock.
loosened:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/first-session.sh --force --loosened

# Play window: GameMode (+ optional sched-ext) while a game runs. Restores locks after.
[positional-arguments]
play *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/play-window.sh "$@"

# Official Whonix KVM (OpenPGP). Clipboard/USB/mic off. Not VirtualBox.
install-whonix:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/install-whonix.sh

start-whonix:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/start-whonix.sh

# Steam (stock Flatpak or Distrobox). Asks overlay locks. Nothing silent.
install-steam:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/install-steam.sh

# Stock install-vpn (IVPN/Mullvad/Proton/Tailscale) — WireGuard first, asked extra origin.
install-vpn:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/install-vpn.sh

# Stock enable-dangerzone. Asks leftover userns/ptrace. Nothing silent.
enable-dangerzone:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/install-dangerzone.sh

# Stock assemble hits our toolbox stubs. Ask set-toolbox on first.
[positional-arguments]
distrobox-assemble *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/wrap-assemble.sh distrobox "$@"

[positional-arguments]
toolbox-assemble *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/wrap-assemble.sh toolbox "$@"

# Stock unfiltered Flathub fights our stamp. Map onto set-flathub full|off.
[positional-arguments]
set-flathub-unfiltered *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/wrap-flathub-unfiltered.sh "$@"

# Proton.me (Mail/Pass/VPN/…). Web first. Official RPM only after SHA512 + asked locks.
install-proton:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/install-proton.sh

# IVPN (ivpn.net). WireGuard first. Official repo only after you accept an extra RPM origin.
install-ivpn:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/install-ivpn.sh

# Mullvad VPN. WireGuard first. Official repo only after you accept an extra RPM origin.
install-mullvad:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/install-mullvad.sh

# Probe Proton/IVPN URLs and version.json (does not install, does not unlock).
check-vendor-installers:
    #!/usr/bin/bash
    exec python3 /usr/libexec/unwoke/vendor.py check --probe-rpm

# Any vendors{} key. New app = JSON stanza, then this command + CI watch/heal.
[positional-arguments]
install-vendor *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/install-vendor.sh "$@"

# Show this overlay's flavor / remotes / policy / store status
unwoke-status:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh status

# Check overlay invariants (harden_userns, flavor browser, no SUID)
audit-unwoke:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh audit

# Prove every overlay addition on this disk. PASS/LOOSE/SKIP/FAIL with proof.
# Does not unlock anything. FAIL means the image is missing what this flavor ships.
unwoke-test:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/selftest.sh

test-unwoke:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/selftest.sh

# System Flathub: off (default, all flavors) | verified | full
[positional-arguments]
set-flathub *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh flathub "$@"

# Flatpak permission lockdown (stock cuts plus extra xdg/host-root). Breaks apps until Flatseal.
[positional-arguments]
set-flatpak-lockdown *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh lockdown "$@"

# Flatpak Pulse/PipeWire record (mic + other apps' audio). Default on. Independent of lockdown.
[positional-arguments]
set-flatpak-record *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh flatpak-record "$@"

# NFS/CIFS client modules. Default off (stock only masks the NFS *server*).
[positional-arguments]
set-network-fs *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh network-fs "$@"

# noexec /dev/shm, /tmp, and /var/tmp. Default locked. Some Electron/old JIT need: on
[positional-arguments]
set-ramdisk-exec *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh ramdisk-exec "$@"

# Intel CET (SHSTK + IBT) glibc tunables. Default on.
[positional-arguments]
set-cet *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh cet "$@"

# chmod 700 /boot. Default on.
[positional-arguments]
set-boot-perm *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh boot-perm "$@"

# Fedora extra CAs vs Mozilla website set. Default trimmed (off).
[positional-arguments]
set-extra-cas *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh extra-cas "$@"

# Origin or Trivalent: HTTPS / metrics / autofill / passwords / translate. Restart the browser after.
[positional-arguments]
set-brave-hardening *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh hardening "$@"

[positional-arguments]
set-trivalent-hardening *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh hardening "$@"

# Origin or Trivalent: block camera/mic/geo/USB/Bluetooth/serial/HID/file-system API. Restart after.
[positional-arguments]
set-brave-devices *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh devices "$@"

[positional-arguments]
set-trivalent-devices *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh devices "$@"

# Origin or Trivalent: block JavaScript JIT (default on; breaks some sites). Restart after.
[positional-arguments]
set-brave-jitless *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh jitless "$@"

[positional-arguments]
set-trivalent-jitless *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh jitless "$@"

# Origin or Trivalent: block all extension installs (default) or allow. Restart after.
[positional-arguments]
set-brave-extensions *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh extensions "$@"

[positional-arguments]
set-trivalent-extensions *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh extensions "$@"

# Origin: wrap the desktop launcher in Bubblejail. Default on. GPU may break.
# Trivalent: refused (stock already jails it; their FAQ says not to Bubblejail it).
[positional-arguments]
set-brave-bubblejail *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh bubblejail "$@"

# Origin or Trivalent: no WebGL/WebGPU, force site/origin isolation. Restart after.
[positional-arguments]
set-brave-isolation *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh isolation "$@"

[positional-arguments]
set-trivalent-isolation *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh isolation "$@"

# Origin or Trivalent: audio sandbox, no screen capture, no JS optimizer. Default on.
[positional-arguments]
set-brave-sandbox *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh sandbox "$@"

[positional-arguments]
set-trivalent-sandbox *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh sandbox "$@"

# Origin or Trivalent: lock chrome://devtools. Default locked.
[positional-arguments]
set-brave-devtools *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh devtools "$@"

[positional-arguments]
set-trivalent-devtools *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh devtools "$@"

# Trivalent only: force Network Service Sandbox (stock leaves this off; may clear cookies).
[positional-arguments]
set-trivalent-network-sandbox *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh network-sandbox "$@"

# Trivalent only: punycode domains + clear-cross-origin-referrers. Some sites may break.
[positional-arguments]
set-trivalent-referrers *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh referrers "$@"

# Homebrew. Default off (stock ships it). New shell after change.
[positional-arguments]
set-brew *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh brew "$@"

# Webcam + ALSA capture lock. Speakers stay. Default locked.
[positional-arguments]
set-camera-mic *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh camera-mic "$@"

# Wheel GUI lock once a non-wheel user exists. TTY/run0 stay. add NAME creates that user.
[positional-arguments]
set-admin-split *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh admin-split "$@"

# Bluetooth. Default off. Wi-Fi is not touched.
[positional-arguments]
set-bluetooth *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh bluetooth "$@"

# toolbox + distrobox. Default off. /usr/bin/toolbox is a wrapper. podman stays.
[positional-arguments]
set-toolbox *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh toolbox "$@"

# Avahi (.local) + ModemManager. Default off. cups/geoclue are stock.
[positional-arguments]
set-extra-daemons *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh extra-daemons "$@"

# Fedora rpm-ostree countme (machine census). Default off.
[positional-arguments]
set-countme *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh countme "$@"

# GNOME/NetworkManager "am I online" HTTP check. Default off. Captive portals may need on.
[positional-arguments]
set-connectivity-check *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh connectivity-check "$@"

# Send hostname + stable DHCPv6 DUID. Default off (RFC 7844-ish).
[positional-arguments]
set-dhcp-hostname *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh dhcp-hostname "$@"

# GNOME Files + Dolphin thumbnails. Default off.
[positional-arguments]
set-thumbnails *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh thumbnails "$@"

# Persistent journal, hibernate-to-disk, coredumps, file indexer. Default off.
[positional-arguments]
set-disk-traces *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh disk-traces "$@"

# TCP timestamps. Default off (less clock-skew leak). on = stock timestamps.
[positional-arguments]
set-anon-net *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh anon-net "$@"

# Local hostname "host". Default unchanged (DHCP still silent). Can break printers.
[positional-arguments]
set-anon-hostname *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh anon-hostname "$@"

# Stock deprecation / update-verify / flatpak-setup user units. Default off (masked).
[positional-arguments]
set-stock-nags *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh stock-nags "$@"

# Chrony NTS (Cloudflare + nts.ntp.se). Default on. Independent of dns-selector.
[positional-arguments]
set-nts *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/nts.sh "$@"

# Re-apply Unwoke wallpaper + accent (GNOME schema / KDE wallpaper). Settings still override.
[positional-arguments]
set-unwoke-theme *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/theme.sh "${1:-apply}"

# Browserless only. Default off. Unlocks Flatpak/rpm-ostree browser installs.
# Confirm with: ujust set-allow-browsers on ALLOW
[positional-arguments]
set-allow-browsers *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh allow-browsers "$@"
