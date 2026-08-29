# Upstream snapshots

Exact copies of stock secureblue files we **do not execute**. CI compares
each snapshot to the live GitHub raw URL. A mismatch fails the watch job
(and uploads the new files) but does **not** stop the overlay: their signed
base (kernel, SELinux, Trivalent) still ships.

Refresh snapshots:

```
bash .github/scripts/sync-upstream-snapshots.sh
```

Then read the diff. Only if behavior improved, port it into the Unwoke
script (`harden-flatpak.sh`, `flatpak-lockdown.sh`) and commit. Auto-merging
their live Python into the running image would undo self-sufficiency.

Runtime never runs `/usr/libexec/secureblue/harden_flatpak.py`. Unwoke uses
`/usr/libexec/unwoke/harden-flatpak.sh` instead.

License of snapshotted files: Apache-2.0 (Secureblue Authors), same as upstream.
