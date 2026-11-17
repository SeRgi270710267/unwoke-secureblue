#!/usr/bin/env python3
"""Delete completed Actions runs older than the ISO artifact window.

ISO artifacts are kept 90 days. This waits 120 days, then deletes at most
20 completed runs per execution. The newest completed run of each workflow
is kept even if the repository has gone quiet. In-progress runs are never
deleted. A manual dispatch defaults to dry-run. The weekly schedule deletes.

    python3 .github/scripts/actions_cleanup.py --selftest
    REPO=owner/name GH_TOKEN=... CLEANUP_MODE=dry-run python3 .github/scripts/actions_cleanup.py
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone

KEEP_DAYS = 120
MAX_DELETE = 20


def parse_time(value: str):
    if not value:
        return None
    return datetime.fromisoformat(str(value).replace("Z", "+00:00"))


def choose(recent: list, old: list, now: datetime, keep_days: int = KEEP_DAYS, limit: int = MAX_DELETE) -> list[int]:
    """Pick completed run ids that are old and are not the newest of their workflow.

    `recent` is the newest completed page. A workflow that does not appear
    there is left alone: its newest run may be the old one, and deleting it
    would drop the last record of a quiet workflow.
    """
    newest: dict[str, int] = {}
    for run in recent:
        path = run.get("path") or run.get("name") or ""
        if path in newest or run.get("id") is None:
            continue
        newest[path] = int(run["id"])
    victims: list[int] = []
    for run in old:
        if run.get("status") != "completed":
            continue
        path = run.get("path") or run.get("name") or ""
        run_id = run.get("id")
        if run_id is None or path not in newest or int(run_id) == newest[path]:
            continue
        started = parse_time(run.get("created_at") or "")
        if started is None:
            continue
        age_days = (now - started).total_seconds() / 86400.0
        if age_days < keep_days:
            continue
        victims.append(int(run_id))
        if len(victims) >= limit:
            break
    return victims


def github_json(url: str, token: str, method: str = "GET"):
    req = urllib.request.Request(
        url,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "User-Agent": "unwoke-actions-cleanup",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as res:
            raw = res.read().decode("utf-8")
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as err:
        if method == "DELETE" and err.code == 204:
            return {}
        detail = err.read().decode("utf-8", "replace")[:300]
        raise RuntimeError(f"GitHub API {err.code} for {method} {url.split('?')[0]}: {detail}") from None


def fetch_runs(repo: str, token: str, query: str) -> list:
    url = f"https://api.github.com/repos/{repo}/actions/runs?per_page=100&{query}"
    data = github_json(url, token)
    return list(data.get("workflow_runs") or [])


def delete_run(repo: str, token: str, run_id: int) -> None:
    url = f"https://api.github.com/repos/{repo}/actions/runs/{run_id}"
    github_json(url, token, method="DELETE")


def _run(run_id: int, path: str, status: str, days_ago: int, now: datetime) -> dict:
    return {
        "id": run_id,
        "path": path,
        "name": path,
        "status": status,
        "created_at": (now - timedelta(days=days_ago)).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }


def selftest() -> int:
    now = datetime(2026, 11, 17, tzinfo=timezone.utc)
    recent = [
        _run(1, ".github/workflows/build.yml", "completed", 1, now),
        _run(2, ".github/workflows/iso.yml", "completed", 2, now),
    ]
    old = [
        _run(1, ".github/workflows/build.yml", "completed", 1, now),
        _run(9, ".github/workflows/build.yml", "completed", 200, now),
        _run(8, ".github/workflows/iso.yml", "in_progress", 200, now),
        _run(7, ".github/workflows/pages.yml", "completed", 30, now),
        _run(6, ".github/workflows/pages.yml", "completed", 130, now),
    ]
    got = choose(recent, old, now)
    assert got == [9], got
    with_pages = recent + [_run(3, ".github/workflows/pages.yml", "completed", 1, now)]
    got_pages = choose(with_pages, old, now)
    assert got_pages == [9, 6], got_pages
    quiet = choose(
        [_run(4, ".github/workflows/build.yml", "completed", 400, now)],
        [_run(4, ".github/workflows/build.yml", "completed", 400, now)],
        now,
    )
    assert quiet == [], quiet
    print("actions cleanup selftest ok")
    return 0


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        return selftest()
    mode = (os.environ.get("CLEANUP_MODE") or "dry-run").strip().lower()
    if mode not in ("dry-run", "delete"):
        print("CLEANUP_MODE must be dry-run or delete", file=sys.stderr)
        return 1
    repo = os.environ.get("REPO") or ""
    token = os.environ.get("GH_TOKEN") or ""
    if not repo or not token:
        print("REPO and GH_TOKEN are required", file=sys.stderr)
        return 1
    now = datetime.now(timezone.utc)
    cutoff = (now - timedelta(days=KEEP_DAYS)).strftime("%Y-%m-%d")
    recent = fetch_runs(repo, token, "status=completed")
    old = fetch_runs(repo, token, f"status=completed&created=%3C{cutoff}")
    victims = choose(recent, old, now)
    print(f"actions cleanup: {len(victims)} run(s) older than {KEEP_DAYS} days, mode {mode}")
    for run_id in victims:
        if mode == "dry-run":
            print(f"dry-run: would delete run {run_id}")
            continue
        delete_run(repo, token, run_id)
        print(f"deleted run {run_id}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as err:
        print(f"actions cleanup failed: {err}", file=sys.stderr)
        sys.exit(1)
