#!/usr/bin/env bash
# Download-flake gate for a bluebuild run.
#
#   classify   exit 0 if every failed job is a one-shot download blip
#              exit 2 if it is a real failure (inspect, needle, key, recipe)
#   rerun      after the run has finished: classify, then
#              `gh run rerun --failed` once. Never call this from inside
#              the bake — GitHub rejects a rerun while the run is still
#              in progress, which is why the old in-job rerun never fired.
#
# Pin-step failures count (cosign "no signatures" after its own 5 tries),
# unless the log says the signing key rotated. Build / Install cosign /
# canary export count only when the log shows a download blip
# (504, curl 22/35, slsa-verifier, cut-off tar). Second attempt is not
# this script's job: flake-rerun.yml only listens to attempt 1.
set -euo pipefail

mode="${1:-classify}"
repo="${FLAKE_REPO:-${GITHUB_REPOSITORY:?}}"
run_id="${FLAKE_RUN_ID:-${GITHUB_RUN_ID:?}}"
here="$(cd "$(dirname "$0")" && pwd)"

export GH_TOKEN="${GH_TOKEN:?}"
export FLAKE_REPO="${repo}"
export FLAKE_RUN_ID="${run_id}"

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

python3 "${here}/flake-rerun.py" fetch-jobs --out "${tmp}/jobs.json"

# Completed failed jobs only. A still-running sibling has no log yet.
gh run view "${run_id}" --repo "${repo}" --log-failed > "${tmp}/logs.txt" || true

set +e
decision="$(python3 "${here}/flake-rerun.py" decide --jobs "${tmp}/jobs.json" --logs "${tmp}/logs.txt")"
rc=$?
set -e
echo "flake-rerun: ${decision}"

if [[ "${mode}" == "classify" ]]; then
  exit "${rc}"
fi
if [[ "${mode}" != "rerun" ]]; then
  echo "usage: rerun-cosign-flake.sh classify|rerun" >&2
  exit 1
fi
if [[ "${rc}" -ne 0 ]]; then
  echo "flake-rerun: not a download flake; leaving the alarm in place"
  exit 0
fi

scheduled=0
for n in 1 2 3 4 5 6; do
  if gh run rerun "${run_id}" --repo "${repo}" --failed; then
    scheduled=1
    break
  fi
  echo "flake-rerun: rerun API not ready (${n}/6); sleep 20" >&2
  sleep 20
done
if [[ "${scheduled}" -ne 1 ]]; then
  echo "flake-rerun: could not rerun; opening factory-alarm" >&2
  GITHUB_RUN_ID="${run_id}" bash "${here}/factory-alarm.sh" open
  exit 1
fi
echo "flake-rerun: scheduled failed-job rerun of ${run_id}"
