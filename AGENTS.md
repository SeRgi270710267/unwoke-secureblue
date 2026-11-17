# AGENTS.md

Guide for any coding agent working in this repository. Read it before you change anything. If this file and another doc disagree, the stricter rule wins.

Distribution is invite-only. The repository may still be public until the owner follows `invite/OWNER-STEPS.md`. Write commits, pull request text, and the public README as if a stranger will read them. Do not put install commands, registry paths, digests, or tokens on the public README or `site-notice/`.

## What this is

Unwoke SecureBlue is an overlay on signed [secureblue](https://secureblue.dev) images (atomic Fedora, bootc, ostree). It is not a fork and it is not affiliated with secureblue. Their kernel hardening, `hardened_malloc`, SELinux, and automatic updates stay.

| Piece | Where |
| --- | --- |
| Image recipes | `recipes/` |
| Overlay scripts, policies, ujust | `files/` |
| Signing public key | `cosign.pub` (the private key is the GitHub secret `SIGNING_SECRET` only) |
| Their public key pin | `keys/secureblue.pub` |
| Factory | `.github/workflows/`, `.github/scripts/` |
| Site | `docs/` (do not edit `docs/secureblue/` by hand) |
| Handoff | `PROGRESS.md` |
| Agent rules and skills | `.agents/rules/`, `.agents/skills/` |

Twelve GHCR images. Recommended default is `unwoke-silverblue-trivalent` or `unwoke-kinoite-trivalent`. Do not docker-pull Atomic images to "test" them. The canary exports with crane and does not run the image.

## Checks

```sh
python3 .github/scripts/secret_scan.py --selftest
python3 .github/scripts/secret_scan.py
python3 .github/scripts/action_pin_guard.py
python3 .github/scripts/workflow_policy.py
bash .github/scripts/shellcheck-tree.sh
python3 files/system/usr/libexec/unwoke/mark-check.py --tree .
```

`pr-gate` (job name **Strict PR gate**) runs these on pull requests. It does not bake. A pull request that changes recipes or `files/` also starts the image workflow. Docs-only pushes do not.

## Shipping

1. Branch from current `origin/main`. One concern per pull request.
2. Every new overlay lock has `ujust … on|off` and stays reversible. If it weakens a lock, it is opt-in and it warns.
3. Overlay files under `files/` and `recipes/` carry `UNWOKE-SHIPPED-FIRST` and the MIT line. Do not put that token in live browser `policies/managed` JSON.
4. Push and open a pull request against `main`. Fill the template. Maintainer merge only. Green CI is not permission to land. There is no auto-merge.
5. Do not force-push `main`. Do not add Dependabot or the Actions app to the `main-strict` bypass list.

Optional commit trailers, when a person should see the change on the site:

```
People: Easy sentence a daily user should read.
Vs: How this is stricter or easier than stock.
Where: Pages now / Next overlay bake / USB ISO
```

Factory-only commits should omit those trailers so the homepage does not pretend the desktop changed.

## Factory rules

- Pin third-party actions to a full commit SHA plus a version comment. Workflow token starts at `permissions: {}`. Each job sets `timeout-minutes`. Long bakes use 360, which is the platform cap, so a healthy bake is not cut short.
- No `pull_request_target`. No auto-merge. Fork pull requests get no secrets.
- Do not move `blue-build/github-action` or the titanoboa pin unless the maintainer asked. Dependabot ignores the image builder on purpose.
- `main` bakes queue. They do not cancel each other. A new push cancels only that pull request's older bake.
- Download blips rerun once (`flake-rerun`). A second failure opens `factory-alarm`. Do not classify a canary hit or a signing-key change as a flake.
- `bake-keepalive` dispatches a bake only when no run has started in 16 hours. It does not retry failures.
- ISO wraps do not run on `on: push`. Do not bump titanoboa to make `iso-alarm` green.

## Hard no

- `gpgcheck=0`, `setenforce 0`, unsigned rebase as a default, firewall off
- Default-off Safe Browsing, fwupd, SELinux, or USBGuard
- A new vendor hostname, Flathub, Snap, or a GUI store to "make it work"
- Secrets, `cosign.key`, `SIGNING_SECRET`, or a pull token in the tree, the image, logs, or chat
- Setting a GHCR package public, uploading an ISO to GHCR, or publishing a digest receipt
- A workflow that grants access from `pull_request` or from a workflow input instead of `invite/allowlist.txt`
- Editing `docs/secureblue/` by hand
- Claiming a stock feature was copied without setting `adopted` in `docs/_tools/stock-feats.json` after a real review

## Alarms

One open issue per label. Do not close `factory-alarm`, `iso-alarm`, or `stock-feats` by hand to make the board look empty. A green bake closes the factory alarm. The weekly all-12 ISO closes `iso-alarm`. Reviewing `stock-feats.json` (`stock_reviewed: keep` or `adopted`) lets Pages close that issue.

Open operational alarms are not a license to weaken a check.
