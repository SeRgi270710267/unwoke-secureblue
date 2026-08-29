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

# Proton.me (Mail/Pass/VPN/…). Web first. Official RPM only after SHA512 + asked locks.
install-proton:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/install-proton.sh

# IVPN (ivpn.net). WireGuard first. Official repo only after you accept an extra RPM origin.
install-ivpn:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/install-ivpn.sh

# Show this overlay's flavor / remotes / policy / store status
unwoke-status:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh status

# Check overlay invariants (harden_userns, flavor browser, no SUID)
audit-unwoke:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh audit

# System Flathub: off (default, all flavors) | verified | full
[positional-arguments]
set-flathub *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh flathub "$@"

# Flatpak permission lockdown (stock cuts, default on). Breaks apps until Flatseal.
[positional-arguments]
set-flatpak-lockdown *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh lockdown "$@"

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

# Origin or Trivalent: lock chrome://devtools. Default allow (opt-in lock).
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

# Stock deprecation / update-verify / flatpak-setup user units. Default off (masked).
[positional-arguments]
set-stock-nags *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh stock-nags "$@"

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
