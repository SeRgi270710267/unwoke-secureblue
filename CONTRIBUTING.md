# Contributing to Unwoke SecureBlue

This overlay is not stock [secureblue](https://secureblue.dev). Do not open overlay bugs on their tracker. Do not send stock patches here.

**Nothing lands on `main` unless [SeRgi270710267](https://github.com/SeRgi270710267) merges it.** There is no auto-merge. There is no committer list. An AI session (including Grok) can help write a patch; it cannot merge.

Site version with the same rules: <https://sergi270710267.github.io/unwoke-secureblue/contributing/>

## How to send work

1. Fork. Branch from current `main`.
2. One concern per PR. Reproducible bug or a small, reversible lock beats an essay.
3. Fill the pull request template. Say what you changed, how to revert it, and that you did not weaken SELinux / USBGuard / Safe Browsing / fwupd / `gpgcheck`.
4. Wait. Canary + `pr-gate` must be green. The maintainer (and, if they ask, a review pass with Grok) has the last word. Silence is not consent.

```
git clone https://github.com/YOUR/unwoke-secureblue
# recipes/   overlay modules
# files/     scripts, SELinux, policies, just
# docs/      the site (not docs/secureblue — that tree is generated)
```

Do not edit `docs/secureblue/` by hand.

## Hard no

- `gpgcheck=0`, `setenforce 0`, unsigned rebase as a default, firewall off
- New vendor **hostname** without an explicit maintainer ack (allowlist is the heal boundary)
- Auto-merge, `pull_request_target` with write to `main`, a new signing key
- Flathub/Snap/unverified as a “fix”
- Bazaar / GNOME Software / Discover
- Secrets, `cosign.key`, `SIGNING_SECRET` in the tree
- “Please adopt the Contributor Covenant”

Every overlay lock must stay **revertable** with `ujust`. Security-first defaults. If a change weakens a lock, it is opt-in and must warn.

## Public mark

Every overlay file under `files/` and `recipes/` must carry `UNWOKE-SHIPPED-FIRST` and the MIT copyright line (`Copyright (c) 2026 SeRgi270710267`). Compose, inspect, and this PR gate fail if a new file is unmarked. Do not obfuscate. Do not change the license. Ideas on stock’s tracker stay public; copies of *this tree* must keep the notice.

## People-facing git

Optional trailers on the commit body (Pages puts them on Home / Compared):

```
People: Easy sentence a daily user should read.
Vs: How this is stricter or easier than stock.
Where: Pages now / Next overlay bake / USB ISO
```

## Security reports

Do not file a public issue for a live RCE in the overlay. Email or a **private** GitHub security advisory to the owner. Stock kernel/Trivalent bugs belong on [secureblue/secureblue](https://github.com/secureblue/secureblue/issues) or their Trivalent repo.

Conduct: [docs/conduct](https://sergi270710267.github.io/unwoke-secureblue/conduct/) — not the Covenant.
