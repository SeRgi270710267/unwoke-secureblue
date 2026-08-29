#!/usr/bin/env python3
"""If a watched stock raw URL 404s, find the same basename once in secureblue/live.

Allowlisted host + repo only. Does not execute their files. Does not change
the expected hash — overlay auto-refresh still copies content after a scan.
"""
from __future__ import annotations

import json
import os
import ssl
import sys
import urllib.error
import urllib.request
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[2]
WATCH = ROOT / ".github" / "scripts" / "upstream-watch.txt"
TREE = "https://api.github.com/repos/secureblue/secureblue/git/trees/live?recursive=1"
ALLOW_HOST = "raw.githubusercontent.com"
ALLOW_PREFIX = "/secureblue/secureblue/live/"
CTX = ssl.create_default_context()


def headers() -> dict[str, str]:
    h = {"User-Agent": "unwoke-stock-relocate", "Accept": "application/vnd.github+json"}
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN") or ""
    if token:
        h["Authorization"] = f"Bearer {token}"
    return h


def fetch(url: str, timeout: int = 30) -> bytes:
    req = urllib.request.Request(url, headers=headers())
    with urllib.request.urlopen(req, timeout=timeout, context=CTX) as resp:
        if resp.status != 200:
            raise RuntimeError(f"{url} HTTP {resp.status}")
        return resp.read()


def allowed_raw(url: str) -> bool:
    p = urlparse(url)
    return p.scheme == "https" and p.hostname == ALLOW_HOST and (p.path or "").startswith(ALLOW_PREFIX)


def load_tree() -> list[str]:
    data = json.loads(fetch(TREE).decode("utf-8"))
    if data.get("truncated"):
        print("relocate: tree truncated; skip", file=sys.stderr)
        return []
    out = []
    for t in data.get("tree") or []:
        if t.get("type") == "blob" and t.get("path"):
            out.append(t["path"])
    return out


def unique_path(basename: str, paths: list[str]) -> str | None:
    hits = [p for p in paths if p == basename or p.endswith("/" + basename)]
    if len(hits) == 1:
        return hits[0]
    if hits:
        print(f"relocate: {basename} matched {len(hits)} paths; skip", file=sys.stderr)
    return None


def probe(url: str) -> bool:
    try:
        fetch(url)
        return True
    except (urllib.error.URLError, TimeoutError, RuntimeError, json.JSONDecodeError):
        return False


def main() -> int:
    if not WATCH.is_file():
        print(f"missing {WATCH}", file=sys.stderr)
        return 1
    lines = WATCH.read_text(encoding="utf-8").splitlines(keepends=True)
    tree: list[str] | None = None
    changed = 0
    out: list[str] = []
    for raw in lines:
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            out.append(raw if raw.endswith("\n") else raw + "\n")
            continue
        parts = stripped.split()
        if len(parts) < 3:
            out.append(raw if raw.endswith("\n") else raw + "\n")
            continue
        sha, url, localp = parts[0], parts[1], parts[2]
        if probe(url):
            out.append(raw if raw.endswith("\n") else raw + "\n")
            continue
        print(f"relocate: 404 or dead {url}")
        if not allowed_raw(url):
            print("relocate: old URL not on allowlisted raw host; skip", file=sys.stderr)
            out.append(raw if raw.endswith("\n") else raw + "\n")
            continue
        if tree is None:
            try:
                tree = load_tree()
            except Exception as exc:
                print(f"relocate: tree fetch failed ({exc})", file=sys.stderr)
                out.append(raw if raw.endswith("\n") else raw + "\n")
                continue
        if not tree:
            out.append(raw if raw.endswith("\n") else raw + "\n")
            continue
        found = unique_path(Path(localp).name, tree)
        if not found:
            print(f"relocate: no unique {Path(localp).name} in live tree", file=sys.stderr)
            out.append(raw if raw.endswith("\n") else raw + "\n")
            continue
        new = f"https://{ALLOW_HOST}{ALLOW_PREFIX}{found}"
        if not allowed_raw(new) or not probe(new):
            print(f"relocate: candidate dead {new}", file=sys.stderr)
            out.append(raw if raw.endswith("\n") else raw + "\n")
            continue
        print(f"relocate: {url} -> {new}")
        out.append(f"{sha} {new} {localp}\n")
        changed += 1
    if changed:
        WATCH.write_text("".join(out), encoding="utf-8", newline="\n")
        print(f"relocate: wrote {WATCH} ({changed} url(s))")
    else:
        print("relocate: no URL moves")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
