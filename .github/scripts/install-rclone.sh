#!/usr/bin/env bash
# Pin: rclone v1.69.3 (linux amd64). Checksum from the release SHA256SUMS.
set -euo pipefail

ver="1.69.3"
sha256="14c841f24de6dfb5b914900b345b02e6a00278ad20e7502041d856a4f1d4e221"
url="https://github.com/rclone/rclone/releases/download/v${ver}/rclone-v${ver}-linux-amd64.zip"
bindir="${HOME}/.local/bin"
mkdir -p "${bindir}"
export PATH="${bindir}:${PATH}"
if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "${bindir}" >> "${GITHUB_PATH}"
fi

if command -v rclone >/dev/null; then
  got="$(rclone version 2>/dev/null || true)"
  if [[ "${got}" == *"${ver}"* ]]; then
    exit 0
  fi
fi

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
curl -fsSL --retry 5 --proto '=https' -o "${tmp}/rclone.zip" "${url}"
echo "${sha256}  ${tmp}/rclone.zip" | sha256sum -c -
unzip -q "${tmp}/rclone.zip" -d "${tmp}"
install -m 0755 "${tmp}/rclone-v${ver}-linux-amd64/rclone" "${bindir}/rclone"
rclone version
