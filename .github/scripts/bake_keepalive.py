#!/usr/bin/env python3
"""Dispatch the overlay bake when GitHub has stopped creating its schedule.

The bake cron is 08:00 and 20:00 UTC. A run that started in the last 16
hours means the schedule is alive, even if that run failed. A queued or
running bake is left alone. This does not retry a failure (flake-rerun
does that once) and it does not cancel a bake that is already going.

    python3 .github/scripts/bake_keepalive.py --selftest
    REPO=owner/name GH_TOKEN=... python3 .github/scripts/bake_keepalive.py --dry-run
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone

STALE_SECONDS = 16 * 60 * 60
ACTIVE = ("in_progress", "queued", "waiting", "pending", "requested")
WORKFLOW = "build.yml"


def parse_time(value: str):
    if not value:
        return None
    return datetime.fromisoformat(str(value).replace("Z", "+00:00"))


def run_started(run: dict):
    return parse_time(run.get("run_started_at") or run.get("created_at") or "")


def on_main(run: dict) -> bool:
    """Pull-request bakes must not look like the twice-daily main schedule."""
    if (run.get("event") or "") == "pull_request":
        return False
    branch = run.get("head_branch") or ""
    return not branch or branch == "main"


def decide(runs, now: datetime) -> tuple[bool, str]:
    """Return whether to workflow_dispatch build.yml, and why.

    runs is newest first. Any active main run, or any main run that
    started inside the stale window, means the schedule is still creating
    work. Pull-request runs are ignored.
    """
    newest_age = None
    newest_id = None
    saw_main = False
    for run in runs:
        if not on_main(run):
            continue
        saw_main = True
        status = run.get("status") or ""
        if status in ACTIVE:
            return False, f"bluebuild {run.get('id')} is {status}"
        started = run_started(run)
        if started is None:
            continue
        age = (now - started).total_seconds()
        if newest_age is None or age < newest_age:
            newest_age = age
            newest_id = run.get("id")
        if age < STALE_SECONDS:
            hours = int(age // 3600)
            return False, f"bluebuild {run.get('id')} started {hours}h ago"
    if not saw_main or newest_age is None:
        return True, "no bluebuild runs on main in the recent list"
    hours = int(newest_age // 3600)
    return True, f"last bluebuild {newest_id} started {hours}h ago"


def github_json(url: str, token: str, method: str = "GET", body: dict | None = None):
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "User-Agent": "unwoke-bake-keepalive",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as res:
            raw = res.read().decode("utf-8")
    except urllib.error.HTTPError as err:
        detail = err.read().decode("utf-8", "replace")[:300]
        raise RuntimeError(f"GitHub API {err.code} for {method} {url.split('?')[0]}: {detail}") from None
    return json.loads(raw) if raw else {}


def fetch_runs(repo: str, token: str) -> list:
    url = f"https://api.github.com/repos/{repo}/actions/workflows/{WORKFLOW}/runs?branch=main&exclude_pull_requests=true&per_page=20"
    data = github_json(url, token)
    return list(data.get("workflow_runs") or [])


def dispatch_bake(repo: str, token: str) -> None:
    url = f"https://api.github.com/repos/{repo}/actions/workflows/{WORKFLOW}/dispatches"
    github_json(url, token, method="POST", body={"ref": "main"})


def _iso(now: datetime, hours_ago: int) -> str:
    return (now - timedelta(hours=hours_ago)).strftime("%Y-%m-%dT%H:%M:%SZ")


def _run(run_id: int, status: str, hours_ago: int, now: datetime) -> dict:
    return {
        "id": run_id,
        "status": status,
        "run_started_at": _iso(now, hours_ago),
    }


def selftest() -> int:
    now = datetime(2026, 11, 17, 12, 0, tzinfo=timezone.utc)
    decision, reason = decide([_run(1, "completed", 12, now)], now)
    assert decision is False and "12h" in reason, reason
    decision, reason = decide([_run(2, "completed", 16, now)], now)
    assert decision is True and "16h" in reason, reason
    decision, reason = decide([_run(3, "in_progress", 20, now)], now)
    assert decision is False and "in_progress" in reason, reason
    decision, reason = decide(
        [_run(4, "completed", 2, now), _run(5, "completed", 20, now)],
        now,
    )
    assert decision is False and "2h" in reason, reason
    decision, reason = decide([_run(6, "failure", 18, now)], now)
    assert decision is True and "18h" in reason, reason
    decision, reason = decide([], now)
    assert decision is True and "no bluebuild" in reason, reason
    decision, reason = decide([{"id": 7, "status": "queued", "head_branch": "main"}], now)
    assert decision is False and "queued" in reason, reason
    pr_run = _run(8, "in_progress", 1, now)
    pr_run["event"] = "pull_request"
    pr_run["head_branch"] = "feature"
    decision, reason = decide([pr_run], now)
    assert decision is True and "no bluebuild runs on main" in reason, reason
    print("bake keepalive selftest ok")
    return 0


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        return selftest()
    dry = "--dry-run" in argv
    repo = os.environ.get("REPO") or ""
    token = os.environ.get("GH_TOKEN") or ""
    if not repo or not token:
        print("REPO and GH_TOKEN are required", file=sys.stderr)
        return 1
    do_dispatch, reason = decide(fetch_runs(repo, token), datetime.now(timezone.utc))
    print(reason)
    if not do_dispatch:
        return 0
    if dry:
        print("dry-run; would dispatch build.yml on main")
        return 0
    dispatch_bake(repo, token)
    print("dispatched build.yml on main")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as err:
        print(f"bake keepalive failed: {err}", file=sys.stderr)
        sys.exit(1)
