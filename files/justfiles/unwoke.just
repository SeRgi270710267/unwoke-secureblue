# Overlay extras. All stock secureblue ujust commands still exist.
# Brave policy commands apply only on Origin images, not -browserless.

# Show this overlay's flavor / userns / store status
unwoke-status:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh status

# Check overlay invariants (harden_userns, brave_t, Brave Origin, no SUID)
audit-unwoke:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh audit

# Brave Origin managed policies (HTTPS-only, no WebRTC leak, no metrics). Restart the browser after.
[positional-arguments]
set-brave-hardening *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh hardening "$@"

# Block JavaScript JIT in Brave Origin (breaks some sites). Restart the browser after.
[positional-arguments]
set-brave-jitless *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh jitless "$@"
