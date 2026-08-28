#!/usr/bin/env bash
# First boot: Brave userns, unfiltered Flathub, then lock the update origin
# onto our signed image so later rpm-ostree upgrades check our cosign stamp.
set -euo pipefail

if command -v semodule >/dev/null; then
  if semodule -l 2>/dev/null | grep -qx 'harden_userns'; then
    semodule --disable=harden_userns || true
  fi
fi

if command -v flatpak >/dev/null; then
  flatpak remote-add --if-not-exists --system flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
fi

promote_signed_origin() {
  command -v rpm-ostree >/dev/null || return 0
  command -v python3 >/dev/null || return 0

  local origin img
  origin="$(rpm-ostree status --json 2>/dev/null | python3 -c '
import json, sys
j = json.load(sys.stdin)
for d in j.get("deployments") or []:
    if d.get("booted"):
        print(d.get("origin") or d.get("container-image-reference") or "")
        break
' || true)"

  case "$origin" in
    ostree-unverified-registry:*)
      img="${origin#ostree-unverified-registry:}"
      echo "unwoke: booted unverified; queuing signed origin ${img}"
      rpm-ostree rebase "ostree-image-signed:docker://${img}" || {
        echo "unwoke: signed rebase failed (network?). Run it later:"
        echo "  rpm-ostree rebase ostree-image-signed:docker://${img}"
        return 0
      }
      echo "unwoke: signed image staged. Reboot once more to lock updates."
      ;;
    ostree-image-signed:*|ostree-remote-image:*)
      echo "unwoke: already on a signed origin"
      ;;
    *)
      echo "unwoke: origin=${origin:-unknown}; not promoting"
      ;;
  esac
}

promote_signed_origin
