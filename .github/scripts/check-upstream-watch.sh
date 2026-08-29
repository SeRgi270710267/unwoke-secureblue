#!/usr/bin/env bash
# Compare watched stock files to our snapshots.
# Does NOT block the overlay: the signed base (kernel, SELinux, Trivalent)
# still ships. A mismatch fails THIS job and uploads the new files so we
# can copy them into snapshots, then update Unwoke's replacement only if
# behavior changed. Runtime never execs their live scripts.
set -euo pipefail

ROOT="${GITHUB_WORKSPACE:-.}"
WATCH="${ROOT}/.github/scripts/upstream-watch.txt"
DRIFT="${ROOT}/upstream-drift"
[[ -f "${WATCH}" ]] || { echo "missing ${WATCH}" >&2; exit 1; }

mkdir -p "${DRIFT}"
fail=0
: > "${DRIFT}/NEW-HASHES.txt"

while IFS= read -r line || [[ -n "${line}" ]]; do
  line="${line%%#*}"
  line="$(printf '%s' "${line}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -n "${line}" ]] || continue
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
  base="$(basename "${localp}")"
  if [[ "${got}" != "${sha}" ]]; then
    echo "DRIFT: stock file changed: ${url}" >&2
    echo "  expected ${sha}" >&2
    echo "  got      ${got}" >&2
    echo "Overlay images still build (kernel follows their signed base)." >&2
    echo "Refresh the snapshot (does not change what the PC runs until you edit Unwoke scripts):" >&2
    echo "  bash .github/scripts/sync-upstream-snapshots.sh" >&2
    echo "  then review files/system/usr/libexec/unwoke/harden-flatpak.sh" >&2
    echo "  and files/system/usr/libexec/unwoke/flatpak-lockdown.sh if lists changed" >&2
    cp -a "${tmp}" "${DRIFT}/${base}"
    printf '%s %s %s\n' "${got}" "${url}" "${localp}" >> "${DRIFT}/NEW-HASHES.txt"
    if [[ -f "${ROOT}/${localp}" ]]; then
      diff -u "${ROOT}/${localp}" "${tmp}" > "${DRIFT}/${base}.diff" || true
      diff -u "${ROOT}/${localp}" "${tmp}" >&2 || true
    fi
    fail=1
  else
    echo "ok: ${localp} still matches stock (${got})"
  fi
  if [[ -f "${ROOT}/${localp}" ]]; then
    loc="$(sha256sum "${ROOT}/${localp}" | awk '{print $1}')"
    if [[ "${loc}" != "${got}" && "${fail}" -eq 0 ]]; then
      echo "FAIL: ${localp} does not match the fetched stock file" >&2
      fail=1
    fi
  else
    echo "FAIL: missing snapshot ${localp}" >&2
    fail=1
  fi
  rm -f "${tmp}"
done < "${WATCH}"

exit "${fail}"
