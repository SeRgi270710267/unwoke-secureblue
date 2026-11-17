#!/usr/bin/env python3
"""Weekly factory health note.

One reused issue. It does not merge anything and it does not close
factory-alarm or iso-alarm (those lanes close themselves when they are
actually green). It does record whether the schedule is still being created,
so a quiet stretch is visible without watching Actions.

    python3 .github/scripts/health_report.py --selftest
    REPO=owner/name GH_TOKEN=... python3 .github/scripts/health_report.py
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone

TITLE = "Factory health"
WORKFLOWS = ("build.yml", "iso.yml", "pages.yml", "verify.yml", "vendor-watch.yml")


def age_hours(stamp: str, now: datetime) -> int | None:
    if not stamp:
        return None
    when = datetime.fromisoformat(stamp.replace("Z", "+00:00"))
    return int((now - when).total_seconds() // 3600)


def line(name: str, run: dict | None, now: datetime) -> str:
    if not run:
        return f"- `{name}`: no completed run in the recent list"
    when = run.get("updated_at") or run.get("created_at") or ""
    hours = age_hours(when, now)
    age = f"{hours}h ago" if hours is not None else "unknown age"
    conclusion = run.get("conclusion") or run.get("status") or "unknown"
    url = run.get("html_url") or ""
    event = run.get("event") or ""
    return f"- `{name}`: **{conclusion}** ({event}, {age}) {url}".rstrip()


def report(runs: dict[str, dict | None], alarms: list[str], dependabot: int, now: datetime) -> str:
    lines = [
        "Weekly look at the factory. This issue does not merge code and does not close a red alarm.",
        "",
        "Scheduled workflows are still enabled. A red `bluebuild` line here can be only the stock-snapshot job: the twelve images may still have been signed. Snapshot drift opens `factory/stock-snapshots` for review instead of failing the USB wrap.",
        "",
        "## Latest completed runs",
    ]
    for name in WORKFLOWS:
        lines.append(line(name, runs.get(name), now))
    lines.append("")
    lines.append("## Open alarms")
    if alarms:
        lines.extend(f"- {item}" for item in alarms)
    else:
        lines.append("- None.")
    lines.append("")
    lines.append("## Waiting on a person")
    lines.append(
        f"- Dependabot pull requests open: **{dependabot}**. Do not auto-merge. "
        "`main-strict` requires your approval and Code Owners. "
        "There is no Actions bypass, and this report will not add one. "
        "The image builder pin is not in those PRs."
    )
    lines.append("")
    lines.append(
        "Auto-merge stays off. A bot cannot satisfy the one-approval rule without a bypass, and a bypass is not used."
    )
    return "\n".join(lines) + "\n"


def github_json(url: str, token: str, method: str = "GET", body: dict | None = None):
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "User-Agent": "unwoke-health-report",
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


def latest_run(repo: str, token: str, workflow: str) -> dict | None:
    url = (
        f"https://api.github.com/repos/{repo}/actions/workflows/{workflow}/runs"
        "?per_page=5&exclude_pull_requests=true"
    )
    data = github_json(url, token)
    runs = data.get("workflow_runs") or []
    return runs[0] if runs else None


def open_alarms(repo: str, token: str) -> list[str]:
    url = f"https://api.github.com/repos/{repo}/issues?state=open&per_page=30"
    data = github_json(url, token)
    found = []
    for issue in data if isinstance(data, list) else []:
        if issue.get("pull_request"):
            continue
        labels = [lab.get("name") or "" for lab in issue.get("labels") or []]
        if any(name.endswith("-alarm") or name in {"stock-feats", "factory-health"} for name in labels):
            found.append(f"#{issue.get('number')} {issue.get('title')}")
    return found


def dependabot_count(repo: str, token: str) -> int:
    url = f"https://api.github.com/repos/{repo}/pulls?state=open&per_page=30"
    data = github_json(url, token)
    count = 0
    for pr in data if isinstance(data, list) else []:
        login = ((pr.get("user") or {}).get("login") or "")
        if login.startswith("dependabot"):
            count += 1
    return count


def upsert_issue(repo: str, token: str, body: str) -> None:
    url = f"https://api.github.com/repos/{repo}/issues?state=open&per_page=20"
    data = github_json(url, token)
    number = None
    for issue in data if isinstance(data, list) else []:
        if issue.get("title") == TITLE and not issue.get("pull_request"):
            number = issue.get("number")
            break
    if number:
        github_json(
            f"https://api.github.com/repos/{repo}/issues/{number}",
            token,
            method="PATCH",
            body={"body": body},
        )
        print(f"updated health issue #{number}")
        return
    created = github_json(
        f"https://api.github.com/repos/{repo}/issues",
        token,
        method="POST",
        body={"title": TITLE, "body": body},
    )
    print(f"opened health issue #{created.get('number')}")


def selftest() -> int:
    now = datetime(2026, 11, 17, 12, tzinfo=timezone.utc)
    text = report(
        {
            "build.yml": {
                "conclusion": "success",
                "event": "schedule",
                "updated_at": "2026-11-17T02:00:00Z",
                "html_url": "https://example.test/run/1",
            },
            "iso.yml": None,
        },
        ["#35 Factory alarm"],
        5,
        now,
    )
    assert "build.yml" in text and "success" in text, text
    assert "#35 Factory alarm" in text
    assert "Dependabot pull requests open: **5**" in text
    assert "Auto-merge stays off" in text
    assert "iso.yml" in text and "no completed run" in text
    print("health report selftest ok")
    return 0


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        return selftest()
    repo = os.environ.get("REPO") or ""
    token = os.environ.get("GH_TOKEN") or ""
    if not repo or not token:
        print("REPO and GH_TOKEN are required", file=sys.stderr)
        return 1
    now = datetime.now(timezone.utc)
    runs = {name: latest_run(repo, token, name) for name in WORKFLOWS}
    body = report(runs, open_alarms(repo, token), dependabot_count(repo, token), now)
    print(body)
    if "--dry-run" in argv:
        return 0
    upsert_issue(repo, token, body)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as err:
        print(f"health report failed: {err}", file=sys.stderr)
        sys.exit(1)
