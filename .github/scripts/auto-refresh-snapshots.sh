#!/usr/bin/env bash
# If stock watched files changed and pass a targeting scan, commit the new
# snapshots + regenerated lockdown lists. Overlay is not blocked.
# Runtime still uses Unwoke scripts, not /usr/libexec/secureblue/*.py.
set -euo pipefail

ROOT="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "${ROOT}"

if bash .github/scripts/check-upstream-watch.sh; then
  echo "snapshots already current"
  exit 0
fi

if [[ ! -d upstream-drift ]] || [[ ! -s upstream-drift/NEW-HASHES.txt ]]; then
  echo "watch failed but no drift files (fetch/path problem)" >&2
  exit 1
fi

needles="${ROOT}/.github/scripts/base-canary-needles.txt"
mapfile -t pats < <(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "${needles}")
for f in upstream-drift/*; do
  [[ -f "${f}" ]] || continue
  [[ "${f}" == *.diff ]] && continue
  [[ "${f}" == *NEW-HASHES.txt ]] && continue
  bytes="$(wc -c < "${f}" | tr -d ' ')"
  if [[ "${bytes}" -lt 20 || "${bytes}" -gt 200000 ]]; then
    echo "SANITY FAIL: ${f} size ${bytes}" >&2
    exit 1
  fi
  for n in "${pats[@]}"; do
    if grep -F -q "${n}" "${f}"; then
      echo "SANITY FAIL: ${f} names this overlay (${n}) — refusing auto-copy" >&2
      exit 1
    fi
  done
done

bash .github/scripts/sync-upstream-snapshots.sh
python3 .github/scripts/extract-flatpak-lockdown-lists.py

if git diff --quiet -- files/upstream-snapshots .github/scripts/upstream-watch.txt files/system/usr/share/unwoke/flatpak-lockdown-lists.sh; then
  echo "nothing to commit"
  exit 0
fi

if [[ "${GITHUB_EVENT_NAME:-}" == "pull_request" ]]; then
  echo "PR: not committing. Review the watch job / artifacts."
  exit 1
fi

git add files/upstream-snapshots .github/scripts/upstream-watch.txt \
  files/system/usr/share/unwoke/flatpak-lockdown-lists.sh
git -c user.name="unwoke-snapshot-bot" \
    -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
    commit -m "chore: refresh stock snapshots (auto)"
git push
echo "committed refreshed snapshots"
