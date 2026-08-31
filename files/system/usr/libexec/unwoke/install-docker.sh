#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Stock ujust install-docker layers Docker CE (root-equivalent daemon).
# Ask leftover container userns. Prefer podman (already on the image).
# Nothing silent.
set -euo pipefail

ask() {
  local prompt="$1" def="${2:-N}"
  local ans=""
  read -r -p "${prompt} [${def}] " ans || true
  ans="${ans:-$def}"
  [[ "${ans}" == [yY] ]]
}

echo
echo "=== Docker (stock ujust install-docker is intercepted) ==="
echo "Podman is already installed and is the Unwoke path. Docker CE is a"
echo "root-equivalent daemon (group docker = root). Stock leftover:"
echo "container-domain user namespaces. Undo later: ujust uninstall-docker"
echo "Nothing silent."
echo

if ! ask "Install Docker CE instead of using podman?" "n"; then
  echo "Keeping podman. Done."
  exit 0
fi

if ! ask "Allow container-domain user namespaces (stock leftover; security cut)?" "n"; then
  echo "Keeping container userns off. Docker will not start until: ujust set-container-userns on"
else
  ujust set-container-userns on || echo "set-container-userns failed"
fi

if command -v ujust >/dev/null && ujust --summary 2>/dev/null | grep -qw install-docker-stock; then
  echo "Running stock install-docker after those questions."
  exec ujust install-docker-stock "$@"
fi
echo "Stock install-docker-stock is not on this image. Prefer podman."
echo "If a leftover stock helper appears after rebase, run that then."
exit 0
