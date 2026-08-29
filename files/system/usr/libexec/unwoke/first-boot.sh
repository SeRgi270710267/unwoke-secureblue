#!/usr/bin/env bash
# Every boot: keep harden_userns on, apply overlay defaults unless the user
# stamped them off, then lock the update origin onto our signed image.
set -euo pipefail

FLAVOR="brave-origin"
if [[ -f /usr/share/unwoke/flavor ]]; then
  FLAVOR="$(tr -d '[:space:]' < /usr/share/unwoke/flavor)"
fi

if command -v semodule >/dev/null; then
  # Older overlay builds disabled this. Put it back; Origin userns is brave_t.
  semodule --enable=harden_userns || true
fi

if [[ "${FLAVOR}" == "browserless" ]]; then
  if [[ -x /usr/libexec/unwoke/browser-guard.sh ]]; then
    /usr/libexec/unwoke/browser-guard.sh apply || true
  fi
elif [[ "${FLAVOR}" == "trivalent" ]]; then
  if command -v restorecon >/dev/null; then
    restorecon -FR /usr/lib64/trivalent /usr/bin/trivalent 2>/dev/null || true
  fi
else
  if command -v restorecon >/dev/null; then
    restorecon -FR /opt/brave.com/brave-origin /usr/bin/brave-origin 2>/dev/null || true
  fi
fi

if [[ -x /usr/libexec/unwoke/toggles.sh ]]; then
  /usr/libexec/unwoke/toggles.sh apply-boot || true
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
