#!/usr/bin/env bash
# Pin: oras-project/oras v1.2.3 (linux amd64).
set -euo pipefail

ver="1.2.3"
need="1.2.3"
sha256="b4efc97a91f471f323f193ea4b4d63d8ff443ca3aab514151a30751330852827"
url="https://github.com/oras-project/oras/releases/download/v${ver}/oras_${ver}_linux_amd64.tar.gz"
bindir="${HOME}/.local/bin"
mkdir -p "${bindir}"
export PATH="${bindir}:${PATH}"
if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "${bindir}" >> "${GITHUB_PATH}"
fi

if command -v oras >/dev/null; then
  got="$(oras version 2>/dev/null || true)"
  if [[ "${got}" == *"${need}"* ]]; then
    exit 0
  fi
fi

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
curl -fsSL --retry 5 -o "${tmp}/oras.tgz" "${url}"
echo "${sha256}  ${tmp}/oras.tgz" | sha256sum -c -
tar -xz -C "${tmp}" -f "${tmp}/oras.tgz" oras
install -m 0755 "${tmp}/oras" "${bindir}/oras"
oras version
