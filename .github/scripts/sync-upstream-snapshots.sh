#!/usr/bin/env bash
# Copy the live stock files into files/upstream-snapshots/ and refresh hashes
# in .github/scripts/upstream-watch.txt.
# Does not change Unwoke runtime scripts. After this, read the diff and
# update harden-flatpak.sh / flatpak-lockdown.sh only if behavior improved.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WATCH="${ROOT}/.github/scripts/upstream-watch.txt"
[[ -f "${WATCH}" ]] || { echo "missing ${WATCH}" >&2; exit 1; }

tmpw="$(mktemp)"
while IFS= read -r line || [[ -n "${line}" ]]; do
  raw="${line}"
  stripped="${line%%#*}"
  stripped="$(printf '%s' "${stripped}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  if [[ -z "${stripped}" ]]; then
    printf '%s\n' "${raw}" >> "${tmpw}"
    continue
  fi
  rest="${stripped#* }"
  url="${rest%% *}"
  localp="${rest#* }"
  tmp="$(mktemp)"
  echo "fetch ${url}"
  curl -fsSL --retry 5 --retry-delay 2 "${url}" -o "${tmp}"
  got="$(sha256sum "${tmp}" | awk '{print $1}')"
  mkdir -p "$(dirname "${ROOT}/${localp}")"
  cp -a "${tmp}" "${ROOT}/${localp}"
  printf '%s %s %s\n' "${got}" "${url}" "${localp}" >> "${tmpw}"
  echo "  ${localp}  ${got}"
  rm -f "${tmp}"
done < "${WATCH}"
mv "${tmpw}" "${WATCH}"
echo
echo "Snapshots updated. git diff files/upstream-snapshots .github/scripts/upstream-watch.txt"
echo "If the diff is a real improvement, port it into the Unwoke script, then commit."
