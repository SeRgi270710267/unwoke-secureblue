#!/usr/bin/env python3
"""Publish stock GitHub FEATs we shipped, with live open/closed from their tracker.

Source of truth for *what we shipped* is stock-feats.json. GitHub only refreshes
title/state/created. Never invents a ticket. Fail-open: snapshot fields in JSON
if the API is unreachable. Rebuilt at Pages deploy.
"""
from __future__ import annotations

import datetime as dt
import html
import json
import os
import ssl
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = Path(__file__).with_name("stock-feats.json")
TEMPLATE = Path(__file__).with_name("stock-feats-template.html")
OUT = ROOT / "docs" / "ahead" / "index.html"
START = "<!-- feats-generated:start -->"
END = "<!-- feats-generated:end -->"
CTX = ssl.create_default_context()
OURS = "https://github.com/SeRgi270710267/unwoke-secureblue"


def esc(s: str) -> str:
    return html.escape(s, quote=True)


def fetch_issue(repo: str, number: int) -> dict | None:
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN") or ""
    url = f"https://api.github.com/repos/{repo}/issues/{number}"
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "unwoke-stock-feats",
            **({"Authorization": f"Bearer {token}"} if token else {}),
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30, context=CTX) as resp:
            return json.load(resp)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
        print(f"stock-feats: #{number} fetch skip ({exc})", flush=True)
        return None


def parse_day(value: str) -> dt.date | None:
    if not value:
        return None
    try:
        return dt.date.fromisoformat(str(value)[:10])
    except ValueError:
        return None


def age_words(days: int) -> str:
    if days < 0:
        days = 0
    if days < 21:
        return f"{days} day" if days == 1 else f"{days} days"
    months = max(1, round(days / 30.44))
    if months == 1:
        return "1 month"
    return f"{months} months"


def merge(item: dict, live: dict | None) -> dict:
    out = dict(item)
    if not live:
        out["state"] = "open"
        return out
    if live.get("title"):
        out["title"] = live["title"]
    if live.get("html_url"):
        out["url"] = live["html_url"]
    if live.get("state"):
        out["state"] = live["state"]
    created = live.get("created_at") or ""
    if created:
        out["created"] = created[:10]
    closed = live.get("closed_at") or ""
    out["closed"] = closed[:10] if closed else ""
    return out


def card(item: dict) -> str:
    created = parse_day(item.get("created") or "")
    shipped = parse_day(item.get("shipped") or "")
    closed = parse_day(item.get("closed") or "")
    state = (item.get("state") or "open").lower()
    ahead = state == "open" or (shipped and closed and closed > shipped)
    wait = ""
    if created and shipped:
        wait = age_words((shipped - created).days)
    if ahead and state == "open":
        status = "Still open on stock"
        klass = "feat-open"
        race = f"Opened {esc(item.get('created') or '—')}. We shipped {esc(item.get('shipped') or '—')}."
        if wait:
            race += f" They had been asking for {esc(wait)}."
    elif state != "open":
        status = "Stock shipped later" if ahead else "On stock"
        klass = "feat-closed"
        race = f"Opened {esc(item.get('created') or '—')}. We shipped {esc(item.get('shipped') or '—')}."
        if closed:
            race += f" They closed {esc(item.get('closed'))}."
    else:
        status = "Shipped here"
        klass = "feat-open"
        race = f"We shipped {esc(item.get('shipped') or '—')}."
    n = int(item["issue"])
    url = item.get("url") or f"https://github.com/secureblue/secureblue/issues/{n}"
    commit = item.get("commit") or ""
    commit_html = ""
    if commit:
        commit_html = (
            f'<a href="{esc(OURS)}/commit/{esc(commit)}">'
            f"<code>{esc(commit[:7])}</code></a>"
        )
    revert = item.get("revert") or ""
    revert_html = ""
    if revert:
        inner = f"<code>{esc(revert)}</code>" if revert.lower().startswith("ujust") or revert.lower().startswith("untick") else esc(revert)
        revert_html = f'<p class="feat-revert"><span>Revert</span> {inner}</p>'
    where = item.get("where") or "compared/"
    return (
        f'      <article class="feat-card {klass}">\n'
        f'        <p class="feat-status">{esc(status)}</p>\n'
        f'        <p class="tag">{esc(item.get("tag") or "Stock")}</p>\n'
        f"        <h3>{esc(item.get('title') or f'#{n}')}</h3>\n"
        f'        <p class="feat-race">{race}</p>\n'
        f"        <p>{esc(item.get('we') or '')}</p>\n"
        f"        {revert_html}\n"
        f'        <p class="feat-links">'
        f'<a href="{esc(url)}">Stock #{n}</a>'
        f"{' · ' + commit_html if commit_html else ''}"
        f' · <a href="{esc(where)}">On Unwoke</a></p>\n'
        f"      </article>\n"
    )


def main() -> int:
    cfg = json.loads(SRC.read_text(encoding="utf-8"))
    repo = cfg.get("repo") or "secureblue/secureblue"
    items = []
    for raw in cfg.get("items") or []:
        n = int(raw["issue"])
        live = fetch_issue(repo, n)
        items.append(merge(raw, live))
    items.sort(key=lambda it: parse_day(it.get("created") or "") or dt.date.max)

    open_n = sum(1 for it in items if (it.get("state") or "open").lower() == "open")
    waits = []
    today = dt.date.today()
    for it in items:
        created = parse_day(it.get("created") or "")
        if created and (it.get("state") or "open").lower() == "open":
            waits.append((today - created).days)
    oldest = age_words(max(waits)) if waits else "—"

    cards = ['    <div class="feat-grid">']
    cards.extend(card(it) for it in items)
    cards.append("    </div>")
    block = "\n".join(cards) + "\n"

    page = TEMPLATE.read_text(encoding="utf-8")
    page = page.replace("__OPEN_N__", str(open_n))
    page = page.replace("__SHIP_N__", str(len(items)))
    page = page.replace("__OLDEST__", esc(oldest))
    if START in page and END in page:
        pre, rest = page.split(START, 1)
        _, post = rest.split(END, 1)
        page = pre + START + "\n" + block + END + post
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(page, encoding="utf-8", newline="\n")
    print(f"wrote {OUT.relative_to(ROOT)} ({len(items)} feats, {open_n} still open)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
