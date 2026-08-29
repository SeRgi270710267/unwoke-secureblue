#!/usr/bin/env bash
# Pin: casey/just 1.42.4 linux musl amd64.
set -euo pipefail

ver="1.42.4"
need="1.42.4"
sha256="678efc1cfbd5fa5a88375daa7e2f3864a049d6d63a0296df925a2ae5f516cb56"
url="https://github.com/casey/just/releases/download/${ver}/just-${ver}-x86_64-unknown-linux-musl.tar.gz"
bindir="${HOME}/.local/bin"
mkdir -p "${bindir}"
export PATH="${bindir}:${PATH}"
if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "${bindir}" >> "${GITHUB_PATH}"
fi

if command -v just >/dev/null; then
  got="$(just --version 2>/dev/null || true)"
  if [[ "${got}" == *"${need}"* ]]; then
    exit 0
  fi
fi

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
curl -fsSL --retry 5 -o "${tmp}/just.tgz" "${url}"
echo "${sha256}  ${tmp}/just.tgz" | sha256sum -c -
tar -xz -C "${tmp}" -f "${tmp}/just.tgz" just
install -m 0755 "${tmp}/just" "${bindir}/just"
just --version
