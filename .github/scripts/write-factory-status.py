#!/usr/bin/env python3
"""Write docs/status.json: last green overlay bake and inspect. Pages only."""
from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs" / "status.json"


def api(url: str) -> dict:
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN") or ""
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "unwoke-factory-status",
            **({"Authorization": f"Bearer {token}"} if token else {}),
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def last_success(owner: str, repo: str, workflow: str) -> dict | None:
    url = (
        f"https://api.github.com/repos/{owner}/{repo}/actions/workflows/"
        f"{workflow}/runs?status=completed&per_page=15"
    )
    try:
        data = api(url)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
        print(f"status: {workflow}: {exc}")
        return None
    for run in data.get("workflow_runs") or []:
        if run.get("conclusion") == "success":
            return {
                "ok": True,
                "id": run.get("id"),
                "html_url": run.get("html_url") or "",
                "updated_at": run.get("updated_at") or run.get("created_at") or "",
                "head_sha": (run.get("head_sha") or "")[:12],
                "display_title": run.get("display_title") or run.get("name") or "",
            }
    return None


def main() -> int:
    repo_full = os.environ.get("GITHUB_REPOSITORY", "SeRgi270710267/unwoke-secureblue")
    owner, _, repo = repo_full.partition("/")
    payload = {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "overlay": last_success(owner, repo, "build.yml"),
        "inspect": last_success(owner, repo, "verify.yml"),
        "iso": last_success(owner, repo, "iso.yml"),
        "vendor": last_success(owner, repo, "vendor-watch.yml"),
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
