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
- [ ] No secrets, keys, or `SIGNING_SECRET` in the diff.
- [ ] Canary still scans their signed base; I did not delete needles to pass CI.

## Tested

-

Maintainer merge only. Green CI is not permission to land.
