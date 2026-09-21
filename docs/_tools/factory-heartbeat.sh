#!/usr/bin/env bash
# If main has had no commits for many days, write a timestamp file so GitHub
# does not disable scheduled workflows (~60 days of no repo activity).
# Does not touch recipes, keys, overlay scripts, or titanoboa.
set -euo pipefail

ROOT="${GITHUB_WORKSPACE:-.}"
cd "${ROOT}"
QUIET_DAYS="${HEARTBEAT_QUIET_DAYS:-10}"

# Age of the commit that started this run (already on origin/main), not a
# local unpushed tutorial/heal commit from an earlier step.
if [[ -n "${GITHUB_SHA:-}" ]] && git cat-file -e "${GITHUB_SHA}^{commit}" 2>/dev/null; then
  last="$(git log -1 --format=%ct "${GITHUB_SHA}")"
else
  last="$(git log -1 --format=%ct origin/HEAD 2>/dev/null || git log -1 --format=%ct)"
fi
now="$(date +%s)"
age_days=$(( (now - last) / 86400 ))
echo "heartbeat: last pushed commit ${age_days}d ago (threshold ${QUIET_DAYS}d)"
if [[ "${age_days}" -lt "${QUIET_DAYS}" ]]; then
  echo "heartbeat: repo is active; no commit"
  exit 0
fi

mkdir -p docs
date -u +"%Y-%m-%dT%H:%M:%SZ" > docs/factory-heartbeat.txt
git add docs/factory-heartbeat.txt
if git diff --cached --quiet; then
  echo "heartbeat: nothing to commit"
  exit 0
fi
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git commit -m "$(cat <<'EOF'
Keep GitHub scheduled workflows alive.

Timestamp only. No overlay, key, or titanoboa change.
EOF
)"

if bash .github/scripts/factory-push.sh; then
  echo "heartbeat: committed factory-heartbeat.txt"
  exit 0
fi

# main-strict blocks the bot. An issue comment is still repository activity,
# so GitHub cron does not die at ~60 days. Overlay is independent. Do not
# open factory-alarm — that lane is canary/bake/inspect.
echo "heartbeat: file did not land; commenting to keep cron enabled"
command -v gh >/dev/null || { echo "gh missing" >&2; exit 0; }
[[ -n "${GITHUB_REPOSITORY:-}" ]] || exit 0
TITLE="Factory heartbeat (cron keep-alive)"
RUN_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID:-unknown}"
BODY="Idle keep-alive so GitHub does not disable scheduled workflows (~60 days of no activity).

The timestamp file could not land on \`main\` (ruleset \`main-strict\` blocks github-actions[bot]). This comment is the keep-alive. Overlay and vendor contracts are independent.

Do not add Dependabot to the bypass list. GitHub Actions does not appear in the bypass search on this personal repo — do not add a stand-in. Do not add a new vendor host here.

- Run: ${RUN_URL}"

num="$(gh issue list --repo "${GITHUB_REPOSITORY}" --state all --search "${TITLE} in:title" --json number,title --jq ".[] | select(.title==\"${TITLE}\") | .number" | head -n1 || true)"
if [[ -n "${num}" ]]; then
  gh issue comment "${num}" --repo "${GITHUB_REPOSITORY}" --body "${BODY}"
  gh issue close "${num}" --repo "${GITHUB_REPOSITORY}" --comment "Keep-alive comment landed. Not an overlay fail." 2>/dev/null || true
else
  url="$(gh issue create --repo "${GITHUB_REPOSITORY}" --title "${TITLE}" --body "${BODY}")"
  echo "heartbeat: ${url}"
  newnum="${url##*/}"
  if [[ "${newnum}" =~ ^[0-9]+$ ]]; then
    gh issue close "${newnum}" --repo "${GITHUB_REPOSITORY}" --comment "Reused next idle window. Not an overlay fail." || true
  fi
fi
echo "heartbeat: keep-alive comment posted"
exit 0
