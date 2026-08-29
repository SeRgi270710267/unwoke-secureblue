#!/usr/bin/env bash
# Notice leftover human gates. Never auto-accept a key or bump titanoboa.
# Lives under docs/_tools so editing it cannot start an overlay bake.
set -euo pipefail

ROOT="${GITHUB_WORKSPACE:-.}"
ALARM="${ROOT}/.github/scripts/issue-alarm.sh"
[[ -f "${ALARM}" ]] || { echo "missing ${ALARM}" >&2; exit 1; }

echo "== stock signing key =="
live="${RUNNER_TEMP:-/tmp}/secureblue-live.pub"
key="${ROOT}/keys/secureblue.pub"
if curl -fsSL --retry 5 --retry-delay 2 \
    "https://raw.githubusercontent.com/secureblue/secureblue/live/cosign.pub" \
    -o "${live}"; then
  if cmp -s "${key}" "${live}"; then
    echo "stock key matches live"
    bash "${ALARM}" key close || true
  else
    echo "STOCK KEY ROTATED — not auto-replacing keys/secureblue.pub"
    diff -u "${key}" "${live}" || true
    bash "${ALARM}" key open
  fi
else
  echo "could not fetch live cosign.pub (transient); skip key alarm"
fi

echo "== titanoboa pin =="
# git ls-remote URL SHA only matches refs (heads/tags named that SHA), not
# commit objects. Our pin is ublue-os/titanoboa@840217d (tag v0.2). Asking
# ls-remote for the SHA opened a false titanoboa-pin issue. Ask GitHub for
# the commit; never bump the pin.
pin_py="${ROOT}/docs/_tools/titanoboa-pin.py"
[[ -f "${pin_py}" ]] || { echo "missing ${pin_py}" >&2; exit 1; }
read -r repo pin < <(python3 "${pin_py}")
echo "pin ${repo}@${pin}"
pin_ok=0
sha=""
if command -v gh >/dev/null && [[ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]]; then
  sha="$(gh api "repos/${repo}/commits/${pin}" --jq .sha 2>/dev/null || true)"
fi
if [[ -z "${sha}" ]]; then
  sha="$(curl -fsSL "https://api.github.com/repos/${repo}/commits/${pin}" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("sha",""))' \
    2>/dev/null || true)"
fi
if [[ -n "${sha}" && "${sha}" == "${pin}"* ]]; then
  pin_ok=1
fi
if [[ "${pin_ok}" -eq 0 ]]; then
  # Last resort: a tag or branch still points at that object.
  if git ls-remote "https://github.com/${repo}.git" | awk '{print $1}' | grep -qi "^${pin}"; then
    pin_ok=1
  fi
fi
if [[ "${pin_ok}" -eq 1 ]]; then
  echo "titanoboa pin still on GitHub (${sha:-${pin}})"
  bash "${ALARM}" pin close || true
else
  echo "TITANOBOA PIN MISSING — not auto-bumping"
  bash "${ALARM}" pin open
fi

echo "== GHCR visibility =="
ALARM=1 bash "${ROOT}/.github/scripts/public-packages.sh"

echo "watch-trust: done"
