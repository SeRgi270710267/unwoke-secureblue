#!/usr/bin/env bash
# First boot: keep harden_userns on, relabel Brave, add Flathub (CLI), then
# lock the update origin onto our signed image.
set -euo pipefail

if command -v semodule >/dev/null; then
  # Older overlay builds disabled this. Put it back; Brave userns is brave_t.
  semodule --enable=harden_userns || true
fi

if command -v restorecon >/dev/null; then
  restorecon -FR /opt/brave.com /usr/bin/brave-browser /usr/bin/brave-browser-stable 2>/dev/null || true
fi

if command -v flatpak >/dev/null; then
  flatpak remote-add --if-not-exists --system flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
fi

if [[ ! -f /etc/unwoke/brave-hardening.off ]]; then
  mkdir -p /etc/brave/policies/managed
  if [[ -f /usr/share/unwoke/brave-hardening.json ]]; then
    cp -a /usr/share/unwoke/brave-hardening.json \
      /etc/brave/policies/managed/10-unwoke-hardening.json || true
  fi
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
