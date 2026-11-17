#!/usr/bin/env bash
# One reusable GitHub issue per factory lane. Does not auto-merge anything.
# Usage: issue-alarm.sh <iso|pages|factory|vendor> open|close
set -euo pipefail

preset="${1:?usage: issue-alarm.sh iso|pages|factory|vendor|key|pin|packages|mirror-cmds|receipt|stock-feats|rehost open|close}"
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
- Image: \`${IMAGE_HINT:-unknown}\`
- Run: ${RUN_URL}

Overlay images can still be green. This lane is only the Titanoboa wrap.
A one-image dispatch that succeeds does **not** close this issue. Only the weekly all-12 wrap may close it.
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
  key)
    TITLE="Stock signing key changed (do not auto-accept)"
    LABEL="stock-key"
    COLOR="B60205"
    DESC="secureblue live cosign.pub differs from keys/secureblue.pub"
    BODY="Their published \`cosign.pub\` no longer matches \`keys/secureblue.pub\`.

- Workflow: \`${GITHUB_WORKFLOW}\`
- SHA: \`${GITHUB_SHA}\`
- Run: ${RUN_URL}

The overlay must not bake on a new key until you check it is really them.
Do **not** auto-replace the file. Compare https://github.com/secureblue/secureblue/blob/live/cosign.pub to \`keys/secureblue.pub\`, then replace only if it is their rotation."
    CLOSE="Stock key matches live again: ${RUN_URL}"
    ;;
  pin)
    TITLE="ISO titanoboa pin is gone (do not auto-bump)"
    LABEL="titanoboa-pin"
    COLOR="D93F0B"
    DESC="Pinned ublue-os/titanoboa commit is missing on GitHub"
    BODY="The USB baker pin in \`.github/workflows/iso.yml\` is not on GitHub anymore (force-push or repo move).

- Workflow: \`${GITHUB_WORKFLOW}\`
- SHA: \`${GITHUB_SHA}\`
- Run: ${RUN_URL}

Do **not** auto-bump to \`@main\`. Read the new commit, pin a hash, re-dispatch ISO."
    CLOSE="Titanoboa pin is fetchable again: ${RUN_URL}"
    ;;
  packages)
    TITLE="GHCR package still public — anonymous pull works"
    LABEL="ghcr-private"
    COLOR="B60205"
    DESC="An Unwoke GHCR package is still anonymously pullable"
    BODY="Anonymous GHCR pull returned 200 for at least one Unwoke package. Invite-only means that pull must fail.

- Workflow: \`${GITHUB_WORKFLOW}\`
- SHA: \`${GITHUB_SHA}\`
- Run: ${RUN_URL}

GitHub does not let a package that is already public be made private again. Do not click Public. Delete the package and let the bake create a new private one, then turn off Inherit access from repository. The repository stays public. Exact order: \`invite/OWNER-STEPS.md\`.

Do not put a pull token in the image or the workflow log. Do not fail the bake for this alarm."
    CLOSE="Anonymous GHCR pull no longer returns 200: ${RUN_URL}"
    ;;
  mirror-cmds)
    TITLE="Stock docs grew a ujust we do not footnote yet"
    LABEL="mirror-cmds"
    COLOR="FBCA04"
    DESC="Mirrored secureblue.dev documents a new set-/toggle-/install-/rebase- command"
    BODY="Stock docs mention a \`ujust\` that is not in \`docs/_tools/stock-unwoke-cmds.json\` and did not auto-pair to an overlay recipe.

- Workflow: \`${GITHUB_WORKFLOW}\`
- SHA: \`${GITHUB_SHA}\`
- Run: ${RUN_URL}

The mirror still injected a \`ujust why\` / \`ujust setup\` box so people are not left with only their snippet. Add a real stanza (needles, Unwoke code, note). Do **not** auto-unlock Flathub/Bluetooth to make their command work. Do not treat this as a canary hit."
    CLOSE="Stock ujust footnotes mapped again: ${RUN_URL}"
    ;;
  receipt)
    TITLE="Public receipt release still exists"
    LABEL="receipt-alarm"
    COLOR="1D76DB"
    DESC="The moving receipt release could not be deleted"
    BODY="The factory could not delete the public \`receipt\` GitHub Release. That release carries a pubkey and image digests.

- Workflow: \`${GITHUB_WORKFLOW}\`
- SHA: \`${GITHUB_SHA}\`
- Run: ${RUN_URL}

Do **not** upload DIGESTS or an ISO. Delete the release and its tag. Steps: \`invite/OWNER-STEPS.md\`."
    CLOSE="Public receipt release is gone: ${RUN_URL}"
    ;;
  stock-feats)
    TITLE="Stock shipped a FEAT we already shipped (review, do not auto-copy)"
    LABEL="stock-feats"
    COLOR="8A6D1F"
    DESC="secureblue closed a GitHub FEAT Unwoke already shipped"
    BODY="Stock closed a feature request we already shipped first. The Shipped first page moved the card to They shipped after us.

- Workflow: \`${GITHUB_WORKFLOW}\`
- SHA: \`${GITHUB_SHA}\`
- Run: ${RUN_URL}
- Page: https://sergi270710267.github.io/unwoke-secureblue/ahead/

Read their PR. If theirs is better, copy it on purpose and set \`adopted.on\` / \`adopted.note\` / \`adopted.commit\` in \`docs/_tools/stock-feats.json\`. If ours stays, set \`stock_reviewed\` to \`keep\`. Do **not** auto-merge their patch. Do not drop the ticket from the page."
    CLOSE="Every stock-after-us FEAT is reviewed (keep or adopted): ${RUN_URL}"
    ;;
  rehost)
    TITLE="Fork or rehost showed up"
    LABEL="rehost-watch"
    COLOR="B60205"
    DESC="A fork of this repo, or another repo using the name, was detected"
    BODY="The public repository was forked, or a search found another repository using the project name. Forks keep a public copy of the source. They do not get the private images.

- Workflow: \`${GITHUB_WORKFLOW}\`
- SHA: \`${GITHUB_SHA}\`
- Run: ${RUN_URL}

This does not delete anyone else's fork. Read it. If they ship the name or the logo, that is a trademark question in \`TRADEMARK.md\`. Do not force-push their repo."
    CLOSE="No fork or same-name repository is listed right now: ${RUN_URL}"
    ;;
  *)
    echo "usage: issue-alarm.sh iso|pages|factory|vendor|key|pin|packages|mirror-cmds|receipt|stock-feats|rehost open|close" >&2
    exit 1
    ;;
esac

if [[ -n "${ALARM_EXTRA:-}" ]]; then
  BODY="${BODY}

${ALARM_EXTRA}"
fi

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
      gh issue edit "${existing}" --repo "${GITHUB_REPOSITORY}" --title "${TITLE}" >/dev/null
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
