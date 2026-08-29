#!/usr/bin/env bash
# Pin: google/go-containerregistry crane v0.20.3 (Linux x86_64).
# Checksum is vendored here so a swapped GitHub asset cannot silently run.
set -euo pipefail

ver="v0.20.3"
need="0.20.3"
sha256="36c67a932f489b3f2724b64af90b599a8ef2aa7b004872597373c0ad694dc059"
url="https://github.com/google/go-containerregistry/releases/download/${ver}/go-containerregistry_Linux_x86_64.tar.gz"
bindir="${HOME}/.local/bin"
mkdir -p "${bindir}"
export PATH="${bindir}:${PATH}"
if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "${bindir}" >> "${GITHUB_PATH}"
fi

ghcr_login() {
  if [[ -n "${GITHUB_TOKEN:-}" ]] && command -v crane >/dev/null; then
    echo "${GITHUB_TOKEN}" | crane auth login ghcr.io -u "${GITHUB_ACTOR:-unwoke}" --password-stdin >/dev/null
  fi
}

if command -v crane >/dev/null; then
  got="$(crane version 2>/dev/null || true)"
  if [[ "${got}" == *"${need}"* ]]; then
    ghcr_login
    exit 0
  fi
fi

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
curl -fsSL --retry 5 -o "${tmp}/crane.tgz" "${url}"
echo "${sha256}  ${tmp}/crane.tgz" | sha256sum -c -
tar -xz -C "${tmp}" -f "${tmp}/crane.tgz" crane
install -m 0755 "${tmp}/crane" "${bindir}/crane"
crane version
ghcr_login
