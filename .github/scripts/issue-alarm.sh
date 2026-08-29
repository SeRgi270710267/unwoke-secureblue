#!/usr/bin/env bash
# One reusable GitHub issue per factory lane. Does not auto-merge anything.
# Usage: issue-alarm.sh <iso|pages|factory|vendor> open|close
set -euo pipefail

preset="${1:?usage: issue-alarm.sh iso|pages|factory|vendor open|close}"
cmd="${2:-open}"
RUN_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"

case "${preset}" in
  factory)
    TITLE="Factory alarm: overlay/canary/watch failed"
    LABEL="factory-alarm"
    COLOR="B60205"
    DESC="Overlay factory failed (canary, watch, build, or inspect)"
    BODY="Automatic factory check failed.

- Workflow: \`${GITHUB_WORKFLOW}\`
- Event: \`${GITHUB_EVENT_NAME}\`
- SHA: \`${GITHUB_SHA}\`
- Run: ${RUN_URL}

This issue is reused (not one per failure). Close it when Actions is green again.
Do not auto-merge a canary hit or a new signing key."
    CLOSE="Factory green again: ${RUN_URL}"
    ;;
  iso)
    TITLE="ISO baker alarm: USB wrap failed"
    LABEL="iso-alarm"
    COLOR="D93F0B"
    DESC="USB ISO wrap or publish failed"
    BODY="The USB ISO baker failed.

- Workflow: \`${GITHUB_WORKFLOW}\`
- Event: \`${GITHUB_EVENT_NAME}\`
- SHA: \`${GITHUB_SHA}\`
- Run: ${RUN_URL}

Overlay images can still be green. This lane is only the Titanoboa wrap.
Do **not** auto-bump the titanoboa pin to make this green. Re-dispatch after a runner flake. A canary/key problem is a factory-alarm, not this issue."
    CLOSE="ISO baker green again: ${RUN_URL}"
    ;;
  pages)
    TITLE="Pages alarm: site deploy failed"
    LABEL="pages-alarm"
    COLOR="FBCA04"
    DESC="GitHub Pages (docs, tutorials hub, factory stamp) failed"
    BODY="GitHub Pages failed to generate or deploy.

- Workflow: \`${GITHUB_WORKFLOW}\`
- SHA: \`${GITHUB_SHA}\`
- Run: ${RUN_URL}

Overlay images are independent. Tutorials hub and the last-green stamp live on this deploy.
Do not weaken locks to make the site build."
    CLOSE="Pages green again: ${RUN_URL}"
    ;;
  vendor)
    TITLE="Vendor installers: contract failed"
    LABEL="vendor-installers"
    COLOR="1D76DB"
    DESC="Vendor installer contract failed"
    BODY="A vendor install URL, version.json schema, or repo file changed or went dark.

- Workflow: \`${GITHUB_WORKFLOW}\`
- SHA: \`${GITHUB_SHA}\`
- Run: ${RUN_URL}

Fix: update \`files/system/usr/share/unwoke/vendor-installers.json\` and/or \`vendor.py\`, then the overlay bake. Do **not** auto-merge a new host, Flathub, or gpgcheck=0."
    CLOSE="Vendor contracts green: ${RUN_URL}"
    ;;
  *)
    echo "usage: issue-alarm.sh iso|pages|factory|vendor open|close" >&2
    exit 1
    ;;
esac

command -v gh >/dev/null || { echo "gh missing" >&2; exit 1; }
[[ -n "${GITHUB_REPOSITORY:-}" ]] || { echo "GITHUB_REPOSITORY unset" >&2; exit 1; }

gh label create "${LABEL}" --repo "${GITHUB_REPOSITORY}" \
  --color "${COLOR}" \
  --description "${DESC}" \
  2>/dev/null || true

existing="$(gh issue list --repo "${GITHUB_REPOSITORY}" --label "${LABEL}" --state open --json number --jq '.[0].number' || true)"
if [[ "${existing}" == "null" ]]; then
  existing=""
fi

case "${cmd}" in
  open)
    if [[ -n "${existing}" ]]; then
      gh issue comment "${existing}" --repo "${GITHUB_REPOSITORY}" --body "${BODY}"
      echo "commented on #${existing} (${LABEL})"
    else
      gh issue create --repo "${GITHUB_REPOSITORY}" --title "${TITLE}" --label "${LABEL}" --body "${BODY}"
    fi
    ;;
  close)
    if [[ -n "${existing}" ]]; then
      gh issue close "${existing}" --repo "${GITHUB_REPOSITORY}" --comment "${CLOSE}"
      echo "closed #${existing} (${LABEL})"
    else
      echo "no open ${LABEL} issue"
    fi
    ;;
  *)
    echo "usage: issue-alarm.sh ${preset} open|close" >&2
    exit 1
    ;;
esac
