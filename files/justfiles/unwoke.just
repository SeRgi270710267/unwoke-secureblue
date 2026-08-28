# Overlay extras. All stock secureblue ujust commands still exist.
# Brave policy commands apply only on Origin images, not -browserless.
# Every overlay hardening switch has on/off/status (or an equivalent revert).

# Show this overlay's flavor / remotes / policy / store status
unwoke-status:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh status

# Check overlay invariants (harden_userns, brave_t, Brave Origin, no SUID)
audit-unwoke:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh audit

# System Flathub: verified (default on Origin) | full | off
[positional-arguments]
set-flathub *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh flathub "$@"

# Flatpak permission lockdown (stock cuts, default on). Breaks apps until Flatseal.
[positional-arguments]
set-flatpak-lockdown *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh lockdown "$@"

# Brave Origin: HTTPS / metrics / autofill / passwords / translate. Restart the browser after.
[positional-arguments]
set-brave-hardening *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh hardening "$@"

# Brave Origin: block camera/mic/geo/USB/Bluetooth/serial/HID/file-system API. Restart after.
[positional-arguments]
set-brave-devices *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh devices "$@"

# Brave Origin: block JavaScript JIT (default on; breaks some sites). Restart after.
[positional-arguments]
set-brave-jitless *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh jitless "$@"

# Brave Origin: block all extension installs (default) or allow. Restart after.
[positional-arguments]
set-brave-extensions *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh extensions "$@"

# Brave Origin: wrap the desktop launcher in Bubblejail. Default off. Experimental.
[positional-arguments]
set-brave-bubblejail *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh bubblejail "$@"

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
