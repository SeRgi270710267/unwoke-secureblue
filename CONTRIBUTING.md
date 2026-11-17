# Contributing to Unwoke SecureBlue

This overlay is not stock [secureblue](https://secureblue.dev). Do not open overlay bugs on their tracker. Do not send stock patches here.

**Nothing lands on `main` unless [SeRgi270710267](https://github.com/SeRgi270710267) merges it.** There is no auto-merge. There is no committer list. An AI session (including Grok) can help write a patch; it cannot merge.

The repository stays public. The github.io site is an invitation notice. The full docs site is behind Cloudflare Access. Do not commit invitee logins or a pull token. An invitee cannot grant anyone else.

## How to send work

1. Fork. Branch from current `main`.
2. One concern per PR. Reproducible bug or a small, reversible lock beats an essay.
3. Fill the pull request template. Say what you changed, how to revert it, and that you did not weaken SELinux / USBGuard / Safe Browsing / fwupd / `gpgcheck`.
4. Wait. Canary + `pr-gate` (job name **Strict PR gate**) must be green. The maintainer (and, if they ask, a review pass with Grok) has the last word. Silence is not consent. GitHub ruleset `main-strict` requires that PR, one approval, Code Owners, and the gate. There is no auto-merge. Owner admin bypass lets the maintainer push `main` so the overlay factory is not blocked on a second account. Factory bot commits (vendor heal, snapshots, heartbeat) need GitHub Actions (app 15368) on that same bypass list — the bot is not an admin. Map: [Factory → GitHub](https://sergi270710267.github.io/unwoke-secureblue/factory/#github).

```
git clone https://github.com/YOUR/unwoke-secureblue
# recipes/   overlay modules
# files/     scripts, SELinux, policies, just
# docs/      the site (not docs/secureblue — that tree is generated)
```

Do not edit `docs/secureblue/` by hand.

## Checks before you push

```sh
python3 .github/scripts/secret_scan.py --selftest
python3 .github/scripts/secret_scan.py
python3 .github/scripts/action_pin_guard.py
python3 .github/scripts/workflow_policy.py
bash .github/scripts/shellcheck-tree.sh
python3 files/system/usr/libexec/unwoke/mark-check.py --tree .
```

Install the same secret scan as a pre-commit hook once: `sh .github/scripts/install_git_hooks.sh`.

Use a GitHub noreply address so a personal mailbox is not stored in commit metadata:

```sh
git config user.email "<id>+<username>@users.noreply.github.com"
```

Also turn on **Settings → Emails → Keep my email addresses private** and **Block command line pushes that expose my email**.

Workflow edits stay pinned to a full commit SHA, start from `permissions: {}`, and do not add `pull_request_target` or auto-merge. Fork pull requests run without secrets. Do not print `SIGNING_SECRET`.

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

Every overlay file under `files/` and `recipes/` must carry `UNWOKE-SHIPPED-FIRST` and the MIT copyright line (`Copyright (c) 2026 SeRgi270710267`). Do not relicense those files in a pull request. A different license is an owner decision recorded in `TRADEMARK.md`. The name and logo are not part of the MIT grant. Compose runs `mark-check.py --apply` so a forgotten file is stamped in the image. Inspect and this PR gate fail if git is still unmarked. Do not put the token into live Chromium/Brave/Trivalent `policies/managed` JSON (the browser would see an extra unrecognized policy). Do not obfuscate. Do not change the license. Do not weaken a lock to “protect credit.” Ideas on stock’s tracker stay public; copies of *this tree* must keep the notice.

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
