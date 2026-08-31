#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Stock enable-dangerzone needs container userns + container-only ptrace (gVisor).
# We ask those leftover stock locks. Overlay extras: none required (podman stays).
set -euo pipefail

ask() {
  local prompt="$1" def="${2:-N}"
  local ans=""
  read -r -p "${prompt} [${def}] " ans || true
  ans="${ans:-$def}"
  [[ "${ans}" == [yY] ]]
}

echo
echo "=== Dangerzone (stock ujust enable-dangerzone is intercepted) ==="
echo "Sandboxed PDF/office sanitizer. Uses Podman + gVisor."
echo "Stock leftover (not overlay): container-domain userns + container-only ptrace."
echo "Toolbox wrappers do not block podman. Nothing silent."
echo

if ! ask "Allow container-domain user namespaces (stock leftover; security cut)?" "n"; then
  echo "Keeping container userns off. Dangerzone will not start until: ujust set-container-userns on"
else
  ujust set-container-userns on || echo "set-container-userns failed"
fi

if ! ask "Allow container-only ptrace (gVisor; stock leftover)?" "n"; then
  echo "Keeping ptrace off. Later: ujust set-ptrace  (container-only if stock offers it)"
else
  ujust set-ptrace on || echo "set-ptrace failed; use leftover stock menu"
fi

if [[ -x /usr/libexec/secureblue/enable_dangerzone.py ]]; then
  echo "Running stock enable-dangerzone after those questions."
  python3 /usr/libexec/secureblue/enable_dangerzone.py "$@" || true
else
  echo "No stock helper on this image. After rebase: leftover enable-dangerzone-stock, or their FAQ."
fi
