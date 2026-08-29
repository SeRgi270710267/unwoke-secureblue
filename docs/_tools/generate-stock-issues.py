#!/usr/bin/env python3
"""List stock secureblue issues that can hit Unwoke, with allowlisted revertable ujust.

Never writes recipes or overlay files. Never suggests setenforce 0 / unsigned rebase.
PRs, CI, Dependabot, and flavors we do not ship are omitted.
"""
from __future__ import annotations

import datetime as dt
import html
import json
import os
import re
import ssl
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MAP = Path(__file__).with_name("stock-issue-map.json")
TEMPLATE = Path(__file__).with_name("stock-issues-template.html")
OUT = ROOT / "docs" / "stock-issues" / "index.html"
API = "https://api.github.com/repos/secureblue/secureblue/issues"
CTX = ssl.create_default_context()
MAX_PAGES = 3
FORBIDDEN = re.compile(
    r"(?i)(setenforce\s*0|gpgcheck\s*=\s*0|selinux.*permissive|ostree-unverified|"
    r"disable (the )?firewall|unsigned rebase)"
)


def fetch(url: str) -> list:
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN") or ""
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "unwoke-stock-issues",
            **({"Authorization": f"Bearer {token}"} if token else {}),
        },
    )
    with urllib.request.urlopen(req, timeout=45, context=CTX) as resp:
        return json.load(resp)


def load_issues() -> list[dict]:
    out: list[dict] = []
    for page in range(1, MAX_PAGES + 1):
        url = f"{API}?state=open&per_page=100&page={page}"
        try:
            chunk = fetch(url)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            print(f"stock-issues: fetch failed ({exc})", file=sys.stderr)
            break
        if not chunk:
            break
        out.extend(chunk)
        if len(chunk) < 100:
            break
    return out


def hay(issue: dict) -> str:
    title = issue.get("title") or ""
    body = issue.get("body") or ""
    labels = " ".join(l.get("name") or "" for l in (issue.get("labels") or []) if isinstance(l, dict))
    return f"{title}\n{body}\n{labels}".lower()


def skip(issue: dict, cfg: dict) -> bool:
    if issue.get("pull_request"):
        return True
    user = ((issue.get("user") or {}).get("login") or "").lower()
    if user in {s.lower() for s in cfg.get("skip_users") or []}:
        return True
    labels = {str(l.get("name") or "").lower() for l in (issue.get("labels") or []) if isinstance(l, dict)}
    if labels & {s.lower() for s in cfg.get("skip_labels") or []}:
        return True
    title = (issue.get("title") or "").lower()
    for s in cfg.get("skip_title") or []:
        if s.lower() in title:
            return True
    if re.fullmatch(
        r"(install-vpn|setup-usbguard|distrobox-assemble|toolbox-assemble)",
        (issue.get("title") or "").strip(),
        re.I,
    ):
        return True
    text = hay(issue)
    only = [s.lower() for s in cfg.get("skip_if_only") or []]
    if only and any(s in text for s in only) and not re.search(
        r"silverblue|kinoite|gnome|plasma|trivalent", text
    ):
        return True
    return False


def _hit(needle: str, text: str) -> bool:
    n = str(needle)
    if any(ch in n for ch in ".*+?[]()"):
        try:
            return re.search(n, text, re.I) is not None
        except re.error:
            return n.lower() in text
    return re.search(r"\b" + re.escape(n) + r"\b", text, re.I) is not None


def match_fixes(issue: dict, cfg: dict) -> list[str]:
    title = (issue.get("title") or "").lower()
    text = hay(issue)
    in_title: list[str] = []
    in_body: list[str] = []
    for rule in cfg.get("rules") or []:
        rid = str(rule.get("id") or "")
        if not rid or rid not in (cfg.get("fixes") or {}):
            continue
        needles = [str(n) for n in (rule.get("any") or [])]
        titled = any(_hit(n, title) for n in needles)
        bodied = any(_hit(n, text) for n in needles)
        if rule.get("title_only") and not titled:
            continue
        if rule.get("need_bug") and "[bug]" not in title:
            continue
        if titled:
            in_title.append(rid)
        elif bodied:
            in_body.append(rid)
    if in_title:
        return list(dict.fromkeys(in_title))
    if "[bug]" in title:
        return list(dict.fromkeys(in_body))
    return []


def excerpt(body: str) -> str:
    t = re.sub(r"```[\s\S]*?```", " ", body or "")
    t = re.sub(r"<[^>]+>", " ", t)
    t = re.sub(r"\s+", " ", t).strip()
    if len(t) > 220:
        t = t[:217] + "…"
    return t


def render_fix(fid: str, spec: dict) -> str:
    code = html.escape(spec.get("code") or "")
    revert = html.escape(spec.get("revert") or "")
    note = html.escape(spec.get("note") or "")
    return (
        f'<div class="alert note unwoke-cmd"><p><strong>Possible Unwoke revert</strong> '
        f"(not applied to the image). Off again: <code>{revert}</code></p>"
        f"<pre><code>{code}</code></pre><p>{note}</p></div>"
    )


def render_item(issue: dict, fix_ids: list[str], fixes: dict) -> str:
    num = issue.get("number")
    title = html.escape(issue.get("title") or f"#{num}")
    url = html.escape(issue.get("html_url") or "", quote=True)
    when = html.escape((issue.get("updated_at") or "")[:10])
    blurb = html.escape(excerpt(issue.get("body") or ""))
    boxes = "\n".join(render_fix(fid, fixes[fid]) for fid in fix_ids if fid in fixes)
    return (
        f'<article class="card issue-card">'
        f'<p class="eyebrow">#{html.escape(str(num))} · {when}</p>'
        f'<h2><a href="{url}">{title}</a></h2>'
        f"{f'<p>{blurb}</p>' if blurb else ''}"
        f"{boxes}"
        f'<p class="mirror-meta">Stock issue. Canonical: <a href="{url}">{url}</a></p>'
        f"</article>"
    )


def main() -> int:
    cfg = json.loads(MAP.read_text(encoding="utf-8"))
    fixes = cfg.get("fixes") or {}
    rows: list[str] = []
    kept = 0
    scanned = 0
    for issue in load_issues():
        scanned += 1
        if skip(issue, cfg):
            continue
        hits = match_fixes(issue, cfg)
        if not hits:
            continue
        if FORBIDDEN.search((issue.get("title") or "") + (issue.get("body") or "")):
            # still list if we have a clean overlay mapping, but never quote their setenforce
            pass
        rows.append(render_item(issue, hits, fixes))
        kept += 1
    inner = "\n".join(rows) if rows else (
        "<p>No open stock issues currently map to an Unwoke-only revertable workaround. "
        "CI, Dependabot, Sway/COSMIC/IoT, and PRs are omitted on purpose.</p>"
    )
    fetched = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    tpl = TEMPLATE.read_text(encoding="utf-8")
    html_out = (
        tpl.replace("__BODY__", inner)
        .replace("__FETCHED__", fetched)
        .replace("__KEPT__", str(kept))
        .replace("__SCANNED__", str(scanned))
    )
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(html_out, encoding="utf-8")
    print(f"stock-issues: {kept} shown / {scanned} scanned -> {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
