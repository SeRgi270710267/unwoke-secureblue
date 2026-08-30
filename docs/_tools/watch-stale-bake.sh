#!/usr/bin/env bash
# Open factory-alarm if overlay bake has not succeeded recently.
# Does not close that issue (only a green bake may close it).
# Lives under docs/_tools so editing it cannot start an overlay bake.
set -euo pipefail

ROOT="${GITHUB_WORKSPACE:-.}"
ALARM="${ROOT}/.github/scripts/factory-alarm.sh"
MAX_AGE_HOURS="${STALE_BAKE_HOURS:-40}"

[[ -f "${ALARM}" ]] || { echo "missing ${ALARM}" >&2; exit 1; }
: "${GITHUB_REPOSITORY:?}"
: "${GH_TOKEN:=${GITHUB_TOKEN:-}}"
[[ -n "${GH_TOKEN}" ]] || { echo "GH_TOKEN unset" >&2; exit 1; }

export GH_TOKEN
python3 - "${MAX_AGE_HOURS}" <<'PY' || status=$?
import json, os, subprocess, sys
from datetime import datetime, timezone

hours = int(sys.argv[1])
repo = os.environ["GITHUB_REPOSITORY"]
raw = subprocess.check_output(
    [
        "gh",
        "api",
        f"repos/{repo}/actions/workflows/build.yml/runs?status=completed&per_page=20",
    ],
    text=True,
)
runs = (json.loads(raw) or {}).get("workflow_runs") or []
last = None
for run in runs:
    if run.get("conclusion") == "success":
        last = run
        break
if last is None:
    print("stale-bake: no successful overlay bake in recent runs")
    raise SystemExit(17)
stamp = last.get("updated_at") or last.get("created_at") or ""
when = datetime.fromisoformat(stamp.replace("Z", "+00:00"))
age = datetime.now(timezone.utc) - when
age_h = age.total_seconds() / 3600.0
url = last.get("html_url") or ""
sha = (last.get("head_sha") or "")[:12]
print(f"stale-bake: last green {sha} {stamp} ({age_h:.1f}h) {url}")
if age_h > hours:
    print(f"stale-bake: older than {hours}h")
    raise SystemExit(17)
raise SystemExit(0)
PY

rc="${status:-0}"
if [[ "${rc}" -eq 17 ]]; then
  echo "stale-bake: opening factory-alarm (no green overlay in ${MAX_AGE_HOURS}h)"
  bash "${ALARM}" open
  exit 0
fi
if [[ "${rc}" -ne 0 ]]; then
  echo "stale-bake: check failed rc=${rc} (do not hide a real factory miss)" >&2
  exit "${rc}"
fi
echo "stale-bake: overlay bake is fresh"
