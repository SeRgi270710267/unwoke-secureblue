---
name: ship-a-pr
description: Takes one Unwoke SecureBlue change from a topic branch to an open pull request. Use when a fix or factory change is ready to review.
---

# Ship a pull request

Follow `AGENTS.md`. Never print `SIGNING_SECRET` or any other secret.

1. **Branch.** `git fetch origin main`, then `git switch -c <topic> origin/main`. One concern.
2. **Change.** Overlay locks stay reversible with `ujust`. Factory edits stay pinned and least-privilege. Do not move the image-builder pin or titanoboa unless the maintainer asked.
3. **Check.**
   ```sh
   python3 .github/scripts/secret_scan.py --selftest
   python3 .github/scripts/secret_scan.py
   python3 .github/scripts/action_pin_guard.py
   python3 .github/scripts/workflow_policy.py
   bash .github/scripts/shellcheck-tree.sh
   python3 files/system/usr/libexec/unwoke/mark-check.py --tree .
   ```
4. **Push and open** a pull request against `main`. Use the template. Say what changed, how to revert it, and that SELinux / USBGuard / Safe Browsing / fwupd / `gpgcheck` were not weakened.
5. **Wait** for **Strict PR gate**. A recipe or `files/` change also starts the image workflow. Do not cancel a `main` bake. You may cancel a superseded run of this same pull request.
6. **Stop** at the open pull request. The maintainer merges. Green CI is not permission to land.
