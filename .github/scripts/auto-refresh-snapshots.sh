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

if bash .github/scripts/factory-push.sh; then
  echo "committed refreshed snapshots on main"
  exit 0
fi

# main-strict blocks github-actions[bot]. A failed push used to fail this
# job, which failed the whole bluebuild workflow, which skipped the USB wrap
# even when all twelve images had just been signed. Open a review PR instead.
# Do not force-push main. This branch is only the snapshot diff.
branch="factory/stock-snapshots"
echo "factory-push declined; updating ${branch} for review"
git fetch origin "${branch}" 2>/dev/null || true
if git rev-parse --verify "origin/${branch}" >/dev/null 2>&1; then
  git push --force-with-lease="refs/heads/${branch}:$(git rev-parse "origin/${branch}")" \
    origin "HEAD:refs/heads/${branch}"
else
  git push origin "HEAD:refs/heads/${branch}"
fi

command -v gh >/dev/null || { echo "gh missing; branch pushed, no PR" >&2; exit 0; }
body="Stock files we snapshot changed. This PR refreshes the hashes and regenerates the lockdown list file from their script.

It does not change Unwoke runtime scripts except \`flatpak-lockdown-lists.sh\` when their permission lists changed. Read that diff. Do not merge if a list got weaker.

The bot cannot push \`main\` (ruleset \`main-strict\`, no Actions bypass). The image bake stays green so the USB wrap is not skipped for a snapshot-only drift.

Do not auto-merge. Do not add a bypass actor."
existing="$(gh pr list --repo "${GITHUB_REPOSITORY}" --head "${branch}" --base main --state open --json number --jq '.[0].number' || true)"
if [[ -n "${existing}" && "${existing}" != "null" ]]; then
  gh pr edit "${existing}" --repo "${GITHUB_REPOSITORY}" --body "${body}"
  echo "updated snapshot PR #${existing}"
else
  gh pr create --repo "${GITHUB_REPOSITORY}" --base main --head "${branch}" \
    --title "Refresh stock snapshots" --body "${body}"
fi
echo "snapshot review PR is open; bake is not failed for this drift"
exit 0
