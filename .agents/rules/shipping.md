---
trigger: always_on
description: "Git and factory shipping rules for the Unwoke SecureBlue overlay."
---

# Shipping

- Branch from current `origin/main`. One concern per pull request. Maintainer merge only. No auto-merge.
- Do not force-push `main`. Do not add Dependabot or GitHub Actions to the `main-strict` bypass list.
- Run the checks in `AGENTS.md` before pushing. Secret scan, action pins, workflow policy, ShellCheck, public mark.
- New overlay locks need `ujust … on|off`. Do not weaken SELinux, USBGuard, Safe Browsing, fwupd, or `gpgcheck`.
- Third-party Actions stay pinned to a full SHA with a version comment. Workflows start at `permissions: {}`. No `pull_request_target`.
- Do not move `blue-build/github-action` or the titanoboa pin unless the maintainer asked.
- Do not make GHCR packages public, upload an ISO as an Actions artifact, publish a digest receipt, or commit invitee logins. Invite steps live in `invite/OWNER-STEPS.md`.
- `main` image bakes queue. They are not cancelled. A pull request's newer push may cancel that pull request's older bake.
- Factory-only commits omit People/Vs/Where trailers.
- Failed Actions are triaged (`triage-failed-actions`). Do not close alarm issues to hide a red bake.
