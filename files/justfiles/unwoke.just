# Overlay extras. All stock secureblue ujust commands still exist.

# Show this overlay's Brave/userns/store status
unwoke-status:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh status

# Check overlay invariants (harden_userns, brave_t, no SUID Brave)
audit-unwoke:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh audit

# Origin Brave managed policies (HTTPS-only, no WebRTC leak, no metrics). Restart Brave after.
[positional-arguments]
set-brave-hardening *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh hardening "$@"

# Block JavaScript JIT in origin Brave (Trivalent-like; breaks some sites). Restart Brave after.
[positional-arguments]
set-brave-jitless *args:
    #!/usr/bin/bash
    exec /usr/libexec/unwoke/toggles.sh jitless "$@"
