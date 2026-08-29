#!/usr/bin/env bash
# Open or update one issue when a vendor installer contract breaks.
# Does not auto-merge URL/schema changes.
set -euo pipefail

cmd="${1:-open}"
TITLE="Vendor installers: Proton/IVPN contract failed"
LABEL="vendor-installers"
RUN_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
BODY="A Proton/IVPN (or other vendor) install URL, version.json schema, or repo file changed or went dark.

- Workflow: \`${GITHUB_WORKFLOW}\`
- SHA: \`${GITHUB_SHA}\`
- Run: ${RUN_URL}

Fix: update \`files/system/usr/share/unwoke/vendor-installers.json\` and/or \`vendor.py\`, then the overlay bake. Do **not** auto-merge. Do not switch to unverified Flathub to “make it work.”"

command -v gh >/dev/null || { echo "gh missing" >&2; exit 1; }

gh label create "${LABEL}" --repo "${GITHUB_REPOSITORY}" \
  --color 1D76DB \
  --description "Vendor installer contract (Proton, IVPN, …) failed" \
  2>/dev/null || true

existing="$(gh issue list --repo "${GITHUB_REPOSITORY}" --label "${LABEL}" --state open --json number --jq '.[0].number' || true)"
if [[ "${existing}" == "null" ]]; then
  existing=""
fi

case "${cmd}" in
  open)
    if [[ -n "${existing}" ]]; then
      gh issue comment "${existing}" --repo "${GITHUB_REPOSITORY}" --body "${BODY}"
    else
      gh issue create --repo "${GITHUB_REPOSITORY}" --title "${TITLE}" --label "${LABEL}" --body "${BODY}"
    fi
    ;;
  close)
    if [[ -n "${existing}" ]]; then
      gh issue close "${existing}" --repo "${GITHUB_REPOSITORY}" \
        --comment "Vendor contracts green: ${RUN_URL}"
    else
      echo "no open vendor-installers issue"
    fi
    ;;
  *)
    echo "usage: vendor-alarm.sh open|close" >&2
    exit 1
    ;;
esac
