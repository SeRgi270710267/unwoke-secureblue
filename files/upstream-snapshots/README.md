# Upstream snapshots

Exact copies of stock secureblue files we **do not execute**. CI compares
each snapshot to the live GitHub raw URL. If they differ, the image build
stops until someone reviews the diff, updates the snapshot, and (only if
behavior changed) updates the Unwoke script that replaced it.

Runtime never runs `/usr/libexec/secureblue/harden_flatpak.py`. Unwoke uses
`/usr/libexec/unwoke/harden-flatpak.sh` instead.

License of snapshotted files: Apache-2.0 (Secureblue Authors), same as upstream.
