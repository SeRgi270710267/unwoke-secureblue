## What

-

## Why Unwoke (not stock)

-

## Revert

- [ ] Every new overlay lock has `ujust … on|off` (or I did not add a lock).
- [ ] I did not default-off Safe Browsing, fwupd, SELinux, USBGuard, or `gpgcheck`.

## Safety

- [ ] No `gpgcheck=0`, `setenforce 0`, unsigned rebase as default, firewall off.
- [ ] No new vendor hostname / Flathub / Snap “to make it work.”
- [ ] No secrets, keys, or `SIGNING_SECRET` in the diff. `python3 .github/scripts/secret_scan.py` is clean.
- [ ] Canary still scans their signed base; I did not delete needles to pass CI.
- [ ] Third-party Actions stay pinned to a full SHA. No `pull_request_target`. No auto-merge.
- [ ] I did not move the `blue-build/github-action` pin or the titanoboa pin unless the maintainer asked.

## Tested

-

Maintainer merge only. Green CI is not permission to land.
