---
trigger: always_on
description: "Locks, signing, and secrets for the Unwoke SecureBlue overlay."
---

# Security locks

- This is an overlay on signed secureblue. It is not affiliated with them and it is not a fork.
- `SIGNING_SECRET` and `cosign.key` exist only as the GitHub secret. Never print, log, or commit them. `cosign.pub` in the repo is public.
- Do not accept a new `keys/secureblue.pub` without the maintainer. The canary must keep failing if the signed base names this repo.
- No `gpgcheck=0`, `setenforce 0`, unsigned rebase as a default, or firewall off.
- No new vendor hostname, Flathub, Snap, or GUI store to make an installer succeed.
- Live browser policy JSON must not contain `UNWOKE-SHIPPED-FIRST`.
- Private vulnerability reports go to a GitHub security advisory, not a public issue. Stock kernel and Trivalent-the-browser bugs go upstream.
- Test on your own machine. Do not docker-pull Atomic images.
