#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# SPDX-License-Identifier: LicenseRef-Unwoke-SA-1.0. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Unwoke Docker prompt. secureblue live has no ujust install-docker
# and no ujust uninstall-docker. Prefer podman (already on the image).
# Docker CE is a root-equivalent daemon. Ask leftover container userns.
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
echo "=== Docker ==="
echo "Podman is already installed and is the Unwoke path. Docker CE is a"
echo "root-equivalent daemon (group docker = root). Current stock has no"
echo "ujust install-docker and no ujust uninstall-docker."
echo "Container-domain user namespaces stay off unless you say yes."
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
echo "No install-docker helper on this image. Docker CE was not installed."
echo "Prefer podman. There is no ujust uninstall-docker."
exit 0
