#!/usr/bin/env python3
"""Decide if a finished bluebuild run failed only on a download blip.

One rerun, started after the run has completed. Never a second rerun.
Never inspect, a canary needle, or a signing-key change.
"""

from __future__ import annotations

import json
import sys

PIN = "Verify and pin official secureblue base"
ALLOW = {
    PIN,
    "Install cosign",
    "Build Custom Image",
    "Scan signed stock base (do not run it)",
}

# A real stop. Do not rerun even if the log also mentions a timeout.
HARD = (
    "does not match secureblue/live/cosign.pub",
    "signing key rotated",
    "refusing to overlay",
    "possible targeted payload",
    "stock base contains /usr/share/unwoke",
    "stock base contains /usr/libexec/unwoke",
)

# Seen on the red bakes while the tree was idle (Sep 2026): GitHub 504,
# curl 22/35, slsa-verifier bootstrap, and a crane/tar cut off mid-download.
NET = (
    "slsa-verifier",
    "unexpected http response: 504",
    "unexpected http response: 503",
    "unexpected http response: 502",
    "curl: (18)",
    "curl: (22)",
    "curl: (28)",
    "curl: (35)",
    "curl: (52)",
    "curl: (56)",
    "exit code 22",
    "exit code 35",
    "exit code 56",
    "connection reset by peer",
    "unexpected end of data",
    "protocol_error",
    "stream error: stream id",
    "could not resolve host",
    "temporary failure in name resolution",
    "tls handshake timeout",
    "i/o timeout",
    "unexpected eof",
    "no signatures found",
    "signing key not found",
    "repomd.xml gpg signature verification error",
    "the operation was aborted due to timeout",
)


def decide(jobs: list, logs_by_name: dict) -> tuple[bool, str]:
    failed = [j for j in jobs if (j or {}).get("conclusion") == "failure"]
    if not failed:
        return False, "no failed jobs"
    for job in failed:
        name = job.get("name") or ""
        steps = [
            (s or {}).get("name") or ""
            for s in (job.get("steps") or [])
            if (s or {}).get("conclusion") == "failure"
        ]
        if not steps or any(step not in ALLOW for step in steps):
            return False, f"not a download flake: {name} failed {steps}"
        log = (logs_by_name.get(name) or "").lower()
        if any(needle in log for needle in HARD):
            return False, f"hard stop in {name}"
        if any(step != PIN for step in steps):
            if not log.strip():
                return False, f"missing log for {name}"
            if not any(sig in log for sig in NET):
                return False, f"no download signature in {name}"
    return True, f"{len(failed)} download flake(s)"


def logs_by_job(text: str) -> dict:
    buckets: dict[str, list[str]] = {}
    for line in text.splitlines():
        if "\t" not in line:
            continue
        job, _, rest = line.partition("\t")
        buckets.setdefault(job, []).append(rest)
    return {name: "\n".join(parts) for name, parts in buckets.items()}


def fetch_jobs(repo: str, run_id: str) -> list:
    import subprocess

    jobs: list = []
    page = 1
    total = None
    while page < 20:
        raw = subprocess.check_output(
            [
                "gh",
                "api",
                f"repos/{repo}/actions/runs/{run_id}/jobs?per_page=100&page={page}",
            ],
            text=True,
        )
        data = json.loads(raw)
        batch = data.get("jobs") or []
        jobs.extend(batch)
        total = data.get("total_count", len(jobs))
        if not batch or len(jobs) >= total:
            break
        page += 1
    return jobs


def load_jobs(path: str) -> list:
    raw = json.loads(open(path, encoding="utf-8").read())
    if isinstance(raw, dict):
        return list(raw.get("jobs") or [])
    if isinstance(raw, list):
        return raw
    raise SystemExit(f"bad jobs json: {path}")


def _job(name: str, steps: list[str]) -> dict:
    return {
        "name": name,
        "conclusion": "failure",
        "steps": [{"name": step, "conclusion": "failure"} for step in steps]
        + [{"name": "Checkout", "conclusion": "success"}],
    }


def self_test() -> int:
    cases = [
        (
            "pin only",
            [_job("Build unwoke-silverblue.yml", [PIN])],
            {},
            True,
        ),
        (
            "pin key rotation",
            [_job("Build unwoke-silverblue.yml", [PIN])],
            {
                "Build unwoke-silverblue.yml": "ERROR: keys/secureblue.pub does not match secureblue/live/cosign.pub\nTheir signing key rotated."
            },
            False,
        ),
        (
            "slsa 504",
            [_job("Build unwoke-kinoite.yml", ["Build Custom Image"])],
            {
                "Build unwoke-kinoite.yml": "Error downloading bootstrap slsa-verifier: Unexpected HTTP response: 504\n##[error]Process completed with exit code 22."
            },
            True,
        ),
        (
            "curl 35",
            [_job("Build unwoke-kinoite-nvidia-open-trivalent.yml", ["Build Custom Image"])],
            {
                "Build unwoke-kinoite-nvidia-open-trivalent.yml": "##[error]Process completed with exit code 35."
            },
            True,
        ),
        (
            "real compose",
            [_job("Build unwoke-kinoite.yml", ["Build Custom Image"])],
            {"Build unwoke-kinoite.yml": "error: module scx-scheds not found in Fedora"},
            False,
        ),
        (
            "inspect",
            [_job("Build unwoke-silverblue.yml", ["Inspect published flavor"])],
            {"Build unwoke-silverblue.yml": "connection reset by peer"},
            False,
        ),
        (
            "canary export reset",
            [_job("Canary ghcr.io/secureblue/silverblue-nvidia-open-hardened", ["Scan signed stock base (do not run it)"])],
            {
                "Canary ghcr.io/secureblue/silverblue-nvidia-open-hardened": "Error: read tcp: connection reset by peer\ntarfile.ReadError: unexpected end of data"
            },
            True,
        ),
        (
            "canary needle",
            [_job("Canary ghcr.io/secureblue/silverblue-main-hardened", ["Scan signed stock base (do not run it)"])],
            {
                "Canary ghcr.io/secureblue/silverblue-main-hardened": "FAIL: official base names this overlay (possible targeted payload in a public image)\nRefusing to overlay"
            },
            False,
        ),
        (
            "mixed flake and inspect",
            [
                _job("Build unwoke-kinoite.yml", ["Build Custom Image"]),
                _job("Build unwoke-silverblue.yml", ["Inspect published flavor"]),
            ],
            {
                "Build unwoke-kinoite.yml": "Unexpected HTTP response: 504",
                "Build unwoke-silverblue.yml": "inspect FAIL",
            },
            False,
        ),
        (
            "receipt cosign",
            [_job("Receipt release", ["Install cosign"])],
            {"Receipt release": "##[error]Process completed with exit code 22."},
            True,
        ),
        (
            "missing build log",
            [_job("Build unwoke-kinoite.yml", ["Build Custom Image"])],
            {},
            False,
        ),
        (
            "watch drift",
            [_job("Watch stock scripts", ["Auto-refresh snapshots on main"])],
            {"Watch stock scripts": "connection reset by peer"},
            False,
        ),
    ]
    failed = 0
    for label, jobs, logs, want in cases:
        got, reason = decide(jobs, logs)
        if got != want:
            print(f"FAIL {label}: got {got} ({reason}) want {want}")
            failed += 1
        else:
            print(f"ok {label}: {reason}")
    if failed:
        print(f"{failed} self-test(s) failed")
        return 1
    print(f"self-test ok ({len(cases)})")
    return 0


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        return self_test()
    if "fetch-jobs" in argv:
        import os

        try:
            out = argv[argv.index("--out") + 1]
        except (ValueError, IndexError):
            print("fetch-jobs needs --out", file=sys.stderr)
            return 1
        repo = os.environ["FLAKE_REPO"]
        run_id = os.environ["FLAKE_RUN_ID"]
        jobs = fetch_jobs(repo, run_id)
        json.dump({"jobs": jobs}, open(out, "w", encoding="utf-8"))
        print(f"flake-rerun: {len(jobs)} jobs")
        return 0
    if "decide" not in argv:
        print("usage: flake-rerun.py --self-test | decide --jobs FILE --logs FILE", file=sys.stderr)
        return 1
    try:
        jobs_path = argv[argv.index("--jobs") + 1]
        logs_path = argv[argv.index("--logs") + 1]
    except (ValueError, IndexError):
        print("decide needs --jobs and --logs", file=sys.stderr)
        return 1
    jobs = load_jobs(jobs_path)
    logs = logs_by_job(open(logs_path, encoding="utf-8", errors="replace").read())
    ok, reason = decide(jobs, logs)
    print(("yes: " if ok else "no: ") + reason)
    return 0 if ok else 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
