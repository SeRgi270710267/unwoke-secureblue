#!/usr/bin/env bash
# Notice forks and other repositories using this name.
# Does not delete anything. Prints counts and repository names, not file contents.
set -euo pipefail

ROOT="${GITHUB_WORKSPACE:-.}"
ALARM="${ROOT}/.github/scripts/issue-alarm.sh"
REPO="${GITHUB_REPOSITORY:?}"
[[ -f "${ALARM}" ]] || { echo "missing ${ALARM}" >&2; exit 1; }
command -v gh >/dev/null
[[ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]] || { echo "no token" >&2; exit 1; }
export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN}}"

forks="$(gh api "repos/${REPO}/forks?per_page=100" --jq 'length' 2>/dev/null || echo "")"
if [[ ! "${forks}" =~ ^[0-9]+$ ]]; then
  echo "rehost-watch: fork list unavailable"
  forks=0
fi
echo "rehost-watch: forks=${forks}"

names=""
search_rc=0
names="$(gh api "search/repositories?q=unwoke-secureblue+in:name&per_page=20" \
  --jq '.items[] | select(.full_name != env.GITHUB_REPOSITORY) | .full_name' 2>/dev/null || true)"
if [[ -z "${names}" ]]; then
  search_rc=0
fi

extra=""
if [[ "${forks}" -gt 0 ]]; then
  extra="Forks listed: ${forks}."
fi
if [[ -n "${names}" ]]; then
  extra="${extra}
Other repositories whose name matches:
"
  while IFS= read -r name; do
    [[ -n "${name}" ]] || continue
    extra="${extra}
- \`${name}\`"
  done <<<"${names}"
fi

if [[ "${forks}" -gt 0 || -n "${names}" ]]; then
  ALARM_EXTRA="${extra}" bash "${ALARM}" rehost open || true
else
  bash "${ALARM}" rehost close || true
fi
if [[ -f "${ROOT}/.github/scripts/cloudflare_access.py" ]]; then
  python3 "${ROOT}/.github/scripts/cloudflare_access.py" seats || echo "rehost-watch: seat check skipped"
fi
if [[ -f "${ROOT}/.github/scripts/r2_iso.py" ]]; then
  python3 "${ROOT}/.github/scripts/r2_iso.py" ops || echo "rehost-watch: r2 ops skipped"
fi
echo "rehost-watch: done"
exit "${search_rc}"
