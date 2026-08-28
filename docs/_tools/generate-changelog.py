#!/usr/bin/env python3
"""Build docs/changelog/ from public git subjects. No bodies, diffs, or secrets."""
from __future__ import annotations

import datetime as dt
import html
import re
import subprocess
import sys
from collections import OrderedDict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs" / "changelog" / "index.html"
TEMPLATE = Path(__file__).with_name("changelog-template.html").read_text(encoding="utf-8")
REPO = "https://github.com/SeRgi270710267/unwoke-secureblue"
MAX = 200

# Drop subjects that look like they might leak credentials or key material.
SENSITIVE = re.compile(
    r"(?i)("
    r"\b(password|passwd|secret|credential|token|private[ _-]?key|api[ _-]?key)\b"
    r"|gh[pousr]_[A-Za-z0-9_]{20,}"
    r"|github_pat_[A-Za-z0-9_]{20,}"
    r"|BEGIN [A-Z ]*PRIVATE KEY"
    r"|AKIA[0-9A-Z]{16}"
    r"|cosign\.key"
    r")"
)
SKIP_PREFIX = re.compile(r"(?i)^(wip|tmp|debug|do not merge)\b")
REDACT = re.compile(
    r"(?i)("
    r"[A-Za-z]:\\[^\s]+"
    r"|/home/[^\s]+"
    r"|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"
    r")"
)


def git(*args: str) -> str:
    r = subprocess.run(
        ["git", *args],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return r.stdout


def entries() -> list[tuple[str, str, str]]:
    raw = git(
        "log",
        "--no-merges",
        "-n",
        str(MAX),
        "--pretty=format:%h%x09%ad%x09%s",
        "--date=short",
    )
    out: list[tuple[str, str, str]] = []
    for line in raw.splitlines():
        parts = line.split("\t", 2)
        if len(parts) != 3:
            continue
        short, day, subject = parts
        subject = subject.strip()
        if not subject or SKIP_PREFIX.search(subject) or SENSITIVE.search(subject):
            continue
        subject = REDACT.sub("[redacted]", subject)
        if SENSITIVE.search(subject):
            continue
        out.append((short, day, subject))
    return out


def render(rows: list[tuple[str, str, str]]) -> str:
    by_day: OrderedDict[str, list[tuple[str, str]]] = OrderedDict()
    for short, day, subject in rows:
        by_day.setdefault(day, []).append((short, subject))
    chunks: list[str] = ['<div class="log">']
    for day, items in by_day.items():
        chunks.append(f'<h2>{html.escape(day)}</h2><ul>')
        for short, subject in items:
            url = f"{REPO}/commit/{html.escape(short, quote=True)}"
            chunks.append(
                "<li>"
                f'<a href="{url}"><code class="hash">{html.escape(short)}</code></a> '
                f"{html.escape(subject)}"
                "</li>"
            )
        chunks.append("</ul>")
    chunks.append("</div>")
    return "\n".join(chunks)


def main() -> int:
    try:
        sha = git("rev-parse", "--short", "HEAD").strip()
        rows = entries()
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        print(f"changelog: git failed ({e})", file=sys.stderr)
        rows = []
        sha = "unknown"
    body = render(rows) if rows else "<p>No public entries yet.</p>"
    fetched = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    html_out = (
        TEMPLATE.replace("__BODY__", body)
        .replace("__FETCHED__", fetched)
        .replace("__SHA__", html.escape(sha))
        .replace("__COUNT__", str(len(rows)))
    )
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(html_out, encoding="utf-8")
    print(f"wrote {OUT} ({len(rows)} entries)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
