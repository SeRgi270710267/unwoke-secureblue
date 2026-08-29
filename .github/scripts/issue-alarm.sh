#!/usr/bin/env bash
# One reusable GitHub issue per factory lane. Does not auto-merge anything.
# Usage: issue-alarm.sh <iso|pages|factory|vendor> open|close
set -euo pipefail

preset="${1:?usage: issue-alarm.sh iso|pages|factory|vendor|key|pin|packages|mirror-cmds|receipt|stock-feats open|close}"
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
    TITLE="GHCR package still private — one Public click"
    LABEL="ghcr-private"
    COLOR="0E8A16"
    DESC="An Unwoke GHCR package is still private after the factory tried to publish it"
    BODY="The factory tried to set Unwoke GHCR packages Public and GitHub still left at least one private. Anonymous rebase/USB fetch needs Public.

- Workflow: \`${GITHUB_WORKFLOW}\`
- SHA: \`${GITHUB_SHA}\`
- Run: ${RUN_URL}

The twelve OS images are often already Public. A USB \`-iso\` GHCR package only exists after oras push succeeds. If the package page 404s, there is nothing to make Public — download the Actions ISO artifact instead.

Working pages are \`https://github.com/OWNER/REPO/pkgs/container/NAME\` (linked) or the repo Packages sidebar. \`/users/.../packages/container/NAME/settings\` 404s/500s.

Do not make the bake fail over this. Do not switch the registry."
    CLOSE="GHCR Unwoke packages are Public: ${RUN_URL}"
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
    TITLE="Receipt release failed (do not upload the ISO)"
    LABEL="receipt-alarm"
    COLOR="1D76DB"
    DESC="The moving GitHub Release tag receipt could not be rewritten"
    BODY="The factory could not rewrite the \`receipt\` GitHub Release (pubkey + verified GHCR digests). Overlay images are independent. This is not a USB host.

- Workflow: \`${GITHUB_WORKFLOW}\`
- SHA: \`${GITHUB_SHA}\`
- Run: ${RUN_URL}

Do **not** attach the ISO (over 2 GiB). Do not auto-accept a new signing key. Next green full verify rewrites the release and closes this."
    CLOSE="Receipt release rewritten: ${RUN_URL}"
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
  *)
    echo "usage: issue-alarm.sh iso|pages|factory|vendor|key|pin|packages|mirror-cmds|receipt|stock-feats open|close" >&2
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
