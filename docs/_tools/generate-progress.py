#!/usr/bin/env python3
"""Publish people-facing progress onto Home, Compared, and Changelog.

Source: git on main (People:/Vs:/Where: trailers, else subject + paths) plus
docs/_tools/people-seed.json for older crafted rows. Factory-only commits stay off
the human pages. Secrets never copied. Rebuilt at Pages deploy.
"""
from __future__ import annotations

import html
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SEED = Path(__file__).with_name("people-seed.json")
COMPARED = ROOT / "docs" / "compared" / "index.html"
HOME = ROOT / "docs" / "index.html"
OUT_JSON = ROOT / "docs" / "progress.json"
REPO = "https://github.com/SeRgi270710267/unwoke-secureblue"
START = "<!-- progress-generated:start -->"
END = "<!-- progress-generated:end -->"
MAX_COMMITS = 120
HOME_N = 6
LEDGER_N = 40

SENSITIVE = re.compile(
    r"(?i)("
    r"\b(password|passwd|secret|credential|token|private[ _-]?key|api[ _-]?key)\b"
    r"|gh[pousr]_[A-Za-z0-9_]{20,}"
    r"|github_pat_[A-Za-z0-9_]{20,}"
    r"|BEGIN [A-Z ]*PRIVATE KEY"
    r"|cosign\.key"
    r")"
)
FACTORY_SUBJECT = re.compile(
    r"(?i)^(chore:|ci:|test:|wip\b|tmp\b)|refresh stock snapshots|harden-runner|"
    r"dependabot|paths-ignore"
)
PEOPLE_PREFIXES = (
    "files/system/",
    "files/justfiles/",
    "recipes/",
    "docs/",
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


def parse_trailers(body: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in body.splitlines():
        m = re.match(r"(?i)^(People|Vs|Where):\s*(.+)$", line.strip())
        if not m:
            continue
        out[m.group(1).lower()] = m.group(2).strip()
    return out


def people_files(files: list[str]) -> list[str]:
    keep = []
    for f in files:
        if f.startswith("docs/_tools/") or f.startswith("docs/factory/"):
            continue
        if any(f.startswith(p) for p in PEOPLE_PREFIXES):
            keep.append(f)
    return keep


def is_people(subject: str, files: list[str], trailers: dict[str, str]) -> bool:
    if trailers.get("people"):
        return True
    if FACTORY_SUBJECT.search(subject):
        return False
    if people_files(files):
        return True
    if any("iso.yml" in f for f in files) and re.search(r"\b(iso|usb)\b", subject, re.I):
        return True
    return False


def infer_where(files: list[str], trailers: dict[str, str]) -> str:
    if trailers.get("where"):
        return trailers["where"]
    bits: list[str] = []
    if any(f.startswith(("files/system/", "files/justfiles/", "recipes/")) for f in files):
        bits.append("Next overlay bake")
    if any(f.startswith("docs/") and not f.startswith("docs/_tools/") for f in files):
        bits.append("Pages now")
    if any("iso.yml" in f for f in files):
        bits.append("USB ISO")
    if any(f.endswith("vendor-installers.json") for f in files):
        bits.append("Strict apps list")
    return "; ".join(bits) or "Changelog"


def norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", s.lower()).strip()[:80]


def load_commits() -> list[dict]:
    try:
        raw = git(
            "log",
            "--no-merges",
            "-n",
            str(MAX_COMMITS),
            "--pretty=format:%H\t%h\t%ad\t%s",
            "--date=short",
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return []
    rows: list[dict] = []
    for line in raw.splitlines():
        parts = line.split("\t", 3)
        if len(parts) != 4:
            continue
        full, short, day, subject = parts
        subject = subject.strip()
        if not subject or SENSITIVE.search(subject):
            continue
        try:
            body = git("show", "-s", "--pretty=format:%B", full)
            names = git("show", "--name-only", "--pretty=format:", full)
        except subprocess.CalledProcessError:
            continue
        files = [n.strip() for n in names.splitlines() if n.strip()]
        trailers = parse_trailers(body)
        if not is_people(subject, files, trailers):
            continue
        what = trailers.get("people") or subject
        if SENSITIVE.search(what):
            continue
        rows.append(
            {
                "day": day,
                "what": what,
                "vs": trailers.get("vs") or "—",
                "where": infer_where(files, trailers),
                "hash": short,
                "url": f"{REPO}/commit/{short}",
            }
        )
    return rows


def load_seed() -> list[dict]:
    if not SEED.is_file():
        return []
    data = json.loads(SEED.read_text(encoding="utf-8"))
    out = []
    for row in data.get("rows") or []:
        what = (row.get("what") or "").strip()
        if not what:
            continue
        out.append(
            {
                "day": row.get("day") or "",
                "what": what,
                "vs": row.get("vs") or "—",
                "where": row.get("where") or "—",
                "hash": "",
                "url": "",
            }
        )
    return out


def merge(git_rows: list[dict], seed: list[dict]) -> list[dict]:
    seen: set[str] = set()
    out: list[dict] = []
    for row in git_rows:
        key = norm(row["what"])
        if not key or key in seen:
            continue
        seen.add(key)
        out.append(row)
        if len(out) >= LEDGER_N:
            break
    for row in seed:
        key = norm(row["what"])
        if not key or key in seen:
            continue
        # skip seed if a git row already covers the same day+gist
        seen.add(key)
        out.append(row)
    return out


def esc(s: str) -> str:
    return html.escape(s, quote=False)


def ledger_html(rows: list[dict]) -> str:
    parts = []
    for row in rows:
        what = esc(row["what"])
        vs = esc(row["vs"])
        where = esc(row["where"])
        day = esc(row["day"])
        if row.get("hash") and row.get("url"):
            what = (
                f'<a href="{html.escape(row["url"], quote=True)}">'
                f'<code class="hash">{html.escape(row["hash"])}</code></a> {what}'
            )
        parts.append(
            "          <tr>\n"
            f"            <td>{day}</td>\n"
            f"            <td>{what}</td>\n"
            f"            <td>{vs}</td>\n"
            f"            <td>{where}</td>\n"
            "          </tr>"
        )
    return "\n".join(parts)


def home_html(rows: list[dict]) -> str:
    items = []
    for row in rows[:HOME_N]:
        what = esc(row["what"])
        day = esc(row["day"])
        items.append(f"        <li><time>{day}</time> {what}</li>")
    inner = "\n".join(items) if items else "        <li>No people-facing git entries yet.</li>"
    return (
        '    <h2 id="whats-new"><a href="#whats-new">What\'s new</a></h2>\n'
        "    <p>Rebuilt with the site from <code>main</code>. Factory-only commits "
        '(alarms, snapshot hashes, CI pins) stay off this list. Score vs stock: '
        '<a href="compared/#ledger">Compared</a>. Every public subject: '
        '<a href="changelog/">Changelog</a>.</p>\n'
        f'    <ul class="whats-new">\n{inner}\n    </ul>'
    )


def inject(path: Path, inner: str) -> None:
    text = path.read_text(encoding="utf-8")
    if START not in text or END not in text:
        raise SystemExit(f"missing {START} markers in {path}")
    pre, rest = text.split(START, 1)
    _, post = rest.split(END, 1)
    path.write_text(pre + START + "\n" + inner + "\n    " + END + post, encoding="utf-8")


def main() -> int:
    git_rows = load_commits()
    rows = merge(git_rows, load_seed())
    OUT_JSON.write_text(
        json.dumps({"rows": rows[:LEDGER_N]}, indent=2) + "\n",
        encoding="utf-8",
    )
    inject(COMPARED, ledger_html(rows))
    inject(HOME, home_html(rows))
    print(f"progress: {len(git_rows)} git people-facing, {len(rows)} ledger rows")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
