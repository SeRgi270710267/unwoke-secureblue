# Security

This overlay sits on [secureblue](https://secureblue.dev). Kernel, SELinux policy they ship, Trivalent-the-browser, USBGuard in stock — report those **upstream**, not here.

**Overlay / our scripts / our GHCR images:** do not file a public issue for a live remote exploit. Use a [private GitHub security advisory](https://github.com/SeRgi270710267/unwoke-secureblue/security/advisories/new) to [SeRgi270710267](https://github.com/SeRgi270710267).

Do not send `SIGNING_SECRET`, `cosign.key`, or GHCR tokens. We will not merge a “fix” that sets `gpgcheck=0`, `setenforce 0`, or unsigned rebase.
