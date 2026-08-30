#!/usr/bin/env bash
# One rerun of this bake, and only if every failed job died on stock
# `cosign verify` of the official base (step "Verify and pin official
# secureblue base"). Never rerun inspect, compose, canary (needles vs
# flake look the same), or a second attempt.
set -euo pipefail

: "${GITHUB_REPOSITORY:?}"
: "${GITHUB_RUN_ID:?}"
: "${GH_TOKEN:?}"

export GH_TOKEN
export PIN='Verify and pin official secureblue base'

if ! python3 -c '
import json, os, subprocess, sys

pin = os.environ["PIN"]
run_id = os.environ["GITHUB_RUN_ID"]
repo = os.environ["GITHUB_REPOSITORY"]
raw = subprocess.check_output(
    [
        "gh",
        "api",
        f"repos/{repo}/actions/runs/{run_id}/jobs?per_page=100",
    ],
    text=True,
)
jobs = (json.loads(raw) or {}).get("jobs") or []
failed = [j for j in jobs if j.get("conclusion") == "failure"]
if not failed:
    print("rerun-cosign-flake: no failed jobs")
    raise SystemExit(0)
for j in failed:
    names = [
        s.get("name") or ""
        for s in (j.get("steps") or [])
        if s.get("conclusion") == "failure"
    ]
    if names != [pin]:
        print(
            "rerun-cosign-flake: not pin-only:",
            j.get("name"),
            "failed",
            names,
            file=sys.stderr,
        )
        raise SystemExit(0)
print(f"rerun-cosign-flake: {len(failed)} pin-only flake(s); rerunning failed jobs")
raise SystemExit(17)
'
then
  rc=$?
  if [[ "${rc}" -eq 17 ]]; then
    gh run rerun "${GITHUB_RUN_ID}" --failed
    echo "rerun-cosign-flake: scheduled failed-job rerun"
    exit 0
  fi
  exit "${rc}"
fi
echo "rerun-cosign-flake: not rerunning"
