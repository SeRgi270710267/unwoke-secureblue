#!/usr/bin/env bash
# Open or update a single GitHub issue when the factory is red.
# Usage: factory-alarm.sh open|close
set -euo pipefail

cmd="${1:-open}"
TITLE="Factory alarm: overlay/canary/watch failed"
LABEL="factory-alarm"
RUN_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
BODY="Automatic factory check failed.

- Workflow: \`${GITHUB_WORKFLOW}\`
- Event: \`${GITHUB_EVENT_NAME}\`
- SHA: \`${GITHUB_SHA}\`
- Run: ${RUN_URL}

This issue is reused (not one per failure). Close it when Actions is green again.
Do not auto-merge a canary hit or a new signing key."

command -v gh >/dev/null || { echo "gh missing" >&2; exit 1; }
[[ -n "${GITHUB_REPOSITORY:-}" ]] || { echo "GITHUB_REPOSITORY unset" >&2; exit 1; }

gh label create "${LABEL}" --repo "${GITHUB_REPOSITORY}" \
  --color B60205 \
  --description "Overlay factory failed (canary, watch, build, or inspect)" \
  2>/dev/null || true

existing="$(gh issue list --repo "${GITHUB_REPOSITORY}" --label "${LABEL}" --state open --json number --jq '.[0].number' || true)"
if [[ "${existing}" == "null" ]]; then
  existing=""
fi

case "${cmd}" in
  open)
    if [[ -n "${existing}" ]]; then
      gh issue comment "${existing}" --repo "${GITHUB_REPOSITORY}" --body "${BODY}"
      echo "commented on #${existing}"
    else
      gh issue create --repo "${GITHUB_REPOSITORY}" --title "${TITLE}" --label "${LABEL}" --body "${BODY}"
    fi
    ;;
  close)
    if [[ -n "${existing}" ]]; then
      gh issue close "${existing}" --repo "${GITHUB_REPOSITORY}" \
        --comment "Factory green again: ${RUN_URL}"
      echo "closed #${existing}"
    else
      echo "no open factory-alarm issue"
    fi
    ;;
  *)
    echo "usage: factory-alarm.sh open|close" >&2
    exit 1
    ;;
esac
