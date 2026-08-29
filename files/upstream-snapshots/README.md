# Upstream snapshots

Exact copies of stock secureblue files we **do not execute**. CI compares
each snapshot to the live GitHub raw URL. A mismatch fails the watch job
(and uploads the new files) but does **not** stop the overlay: their signed
base (kernel, SELinux, Trivalent) still ships.

On main, CI runs `.github/scripts/auto-refresh-snapshots.sh`: if stock
changed and the new file does not name this overlay, it commits the snapshot
and regenerates `files/system/usr/share/unwoke/flatpak-lockdown-lists.sh`.
The PC still runs Unwoke scripts. `/usr/libexec/secureblue/harden_flatpak.py`
in the image is an Unwoke trampoline to `/usr/libexec/unwoke/harden-flatpak.sh`.

Manual refresh (same as CI):

```
bash .github/scripts/sync-upstream-snapshots.sh
python3 .github/scripts/extract-flatpak-lockdown-lists.py
```

Stock `ujust harden-flatpak` still hits `/usr/libexec/secureblue/harden_flatpak.py`,
but that path is an Unwoke trampoline (`os.execv` to
`/usr/libexec/unwoke/harden-flatpak.sh`). The snapshot is for drift detection
only and is never executed.

License of snapshotted files: Apache-2.0 (Secureblue Authors), same as upstream.
