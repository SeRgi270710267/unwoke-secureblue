# Upstream snapshots

Exact copies of stock secureblue files we **do not execute**. CI compares
each snapshot to the live GitHub raw URL. A mismatch fails the watch job
(and uploads the new files) but does **not** stop the overlay: their signed
base (kernel, SELinux, Trivalent) still ships.

On main, CI runs `.github/scripts/auto-refresh-snapshots.sh`: if stock
changed and the new file does not name this overlay, it commits the snapshot
and regenerates `files/system/usr/share/unwoke/flatpak-lockdown-lists.sh`.
The PC still runs Unwoke scripts, not `/usr/libexec/secureblue/*.py`.

Manual refresh (same as CI):

```
bash .github/scripts/sync-upstream-snapshots.sh
python3 .github/scripts/extract-flatpak-lockdown-lists.py
```

Runtime never runs `/usr/libexec/secureblue/harden_flatpak.py`. Unwoke uses
`/usr/libexec/unwoke/harden-flatpak.sh` instead.

License of snapshotted files: Apache-2.0 (Secureblue Authors), same as upstream.
