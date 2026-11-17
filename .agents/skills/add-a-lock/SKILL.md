---
name: add-a-lock
description: Adds a reversible Unwoke overlay lock with ujust on and off. Use for a new default restriction.
---

# Add a lock

1. **Default closed.** The lock is on unless the person opts out. If it weakens an existing lock, it is opt-in and the command warns.
2. **Revert.** Add `ujust set-<name> on|off` in `files/justfiles/unwoke.just` and the matching script under `files/system/usr/libexec/unwoke/`. `on` restores the previous behavior. `off` is the stricter default when that is the house policy. Match the existing toggles.
3. **Do not cut** SELinux, USBGuard, Safe Browsing, fwupd, `gpgcheck`, or the signed rebase.
4. **Mark** new files under `files/` and `recipes/` with `UNWOKE-SHIPPED-FIRST` and `SPDX-License-Identifier: LicenseRef-Unwoke-SA-1.0`. Keep that token out of live browser `policies/managed` JSON. Do not relicense Apache-2.0 paths in `NOTICE`.
5. **No new trust.** No new vendor hostname, Flathub, Snap, or GUI store. No new signing key.
6. **Check** with the commands in `AGENTS.md`, then ship with `ship-a-pr`. Name the `ujust` command in the pull request.
