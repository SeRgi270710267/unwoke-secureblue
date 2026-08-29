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
pin="$(python3 - <<'PY'
from pathlib import Path
import re, sys
text = Path(".github/workflows/iso.yml").read_text(encoding="utf-8")
m = re.search(
    r"repository:\s*ublue-os/titanoboa\s*\n\s*ref:\s*([0-9a-f]{7,40})",
    text,
)
if not m:
    sys.exit("could not parse titanoboa pin from iso.yml")
print(m.group(1))
PY
)"
echo "pin ${pin}"
if git ls-remote "https://github.com/ublue-os/titanoboa.git" "${pin}" | grep -q .; then
  echo "titanoboa pin still on GitHub"
  bash "${ALARM}" pin close || true
else
  echo "TITANOBOA PIN MISSING — not auto-bumping"
  bash "${ALARM}" pin open
fi

echo "== GHCR visibility =="
ALARM=1 bash "${ROOT}/.github/scripts/public-packages.sh"

echo "watch-trust: done"
