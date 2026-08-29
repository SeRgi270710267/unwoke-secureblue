#!/usr/bin/env bash
# Fail if a watched stock file no longer matches our snapshot.
# That is the "they improved it" signal: review the diff, update the
# snapshot, and only then change Unwoke's replacement script if needed.
set -euo pipefail

ROOT="${GITHUB_WORKSPACE:-.}"
WATCH="${ROOT}/.github/scripts/upstream-watch.txt"
[[ -f "${WATCH}" ]] || { echo "missing ${WATCH}" >&2; exit 1; }

fail=0
while IFS= read -r line || [[ -n "${line}" ]]; do
  line="${line%%#*}"
  line="$(printf '%s' "${line}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -n "${line}" ]] || continue
  # sha256  url  local-path
  sha="${line%% *}"
  rest="${line#* }"
  url="${rest%% *}"
  localp="${rest#* }"
  [[ -n "${sha}" && -n "${url}" && -n "${localp}" ]] || {
    echo "bad watch line: ${line}" >&2
    fail=1
    continue
  }
  tmp="$(mktemp)"
  if ! curl -fsSL --retry 5 --retry-delay 2 "${url}" -o "${tmp}"; then
    echo "FAIL: could not fetch ${url}" >&2
    echo "If the path moved, update .github/scripts/upstream-watch.txt" >&2
    rm -f "${tmp}"
    fail=1
    continue
  fi
  got="$(sha256sum "${tmp}" | awk '{print $1}')"
  if [[ "${got}" != "${sha}" ]]; then
    echo "FAIL: stock file changed: ${url}" >&2
    echo "  expected ${sha}" >&2
    echo "  got      ${got}" >&2
    echo "Review the diff, then:" >&2
    echo "  1. copy the new file to ${localp}" >&2
    echo "  2. put the new sha256 in .github/scripts/upstream-watch.txt" >&2
    echo "  3. if behavior changed, update files/system/usr/libexec/unwoke/harden-flatpak.sh" >&2
    if [[ -f "${ROOT}/${localp}" ]]; then
      diff -u "${ROOT}/${localp}" "${tmp}" >&2 || true
    fi
    fail=1
  else
    echo "ok: ${localp} still matches stock (${got})"
  fi
  if [[ -f "${ROOT}/${localp}" ]]; then
    loc="$(sha256sum "${ROOT}/${localp}" | awk '{print $1}')"
    if [[ "${loc}" != "${got}" && "${fail}" -eq 0 ]]; then
      echo "FAIL: ${localp} does not match the fetched stock file (snapshot drifted from watch hash?)" >&2
      fail=1
    fi
  else
    echo "FAIL: missing snapshot ${localp}" >&2
    fail=1
  fi
  rm -f "${tmp}"
done < "${WATCH}"

exit "${fail}"
