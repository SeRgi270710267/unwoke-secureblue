#!/usr/bin/env bash
# If main has had no commits for many days, write a timestamp file so GitHub
# does not disable scheduled workflows (~60 days of no repo activity).
# Does not touch recipes, keys, overlay scripts, or titanoboa.
set -euo pipefail

ROOT="${GITHUB_WORKSPACE:-.}"
cd "${ROOT}"
QUIET_DAYS="${HEARTBEAT_QUIET_DAYS:-10}"

last="$(git log -1 --format=%ct)"
now="$(date +%s)"
age_days=$(( (now - last) / 86400 ))
echo "heartbeat: last commit ${age_days}d ago (threshold ${QUIET_DAYS}d)"
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
git push origin HEAD
echo "heartbeat: committed factory-heartbeat.txt"
