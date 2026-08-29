#!/usr/bin/env python3
"""Track stock GitHub FEATs we shipped first. Never drops a ticket.

Live GitHub only refreshes title/state/closed/PR. What *we* shipped is
stock-feats.json. If they close a ticket after our ship date, the card
stays and says they shipped AFTER us. Do not auto-copy their patch.
If a human later takes their approach, set adopted{} in the JSON.
"""
from __future__ import annotations

import datetime as dt
import html
import json
import os
import re
import ssl
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = Path(__file__).with_name("stock-feats.json")
TEMPLATE = Path(__file__).with_name("stock-feats-template.html")
OUT = ROOT / "docs" / "ahead" / "index.html"
CATCH = ROOT / "docs" / "ahead" / "catch-up.txt"
LEDGER_DOCS = ROOT / "docs" / "ahead" / "SHIPPED-FIRST.txt"
LEDGER_IMG = ROOT / "files" / "system" / "usr" / "share" / "unwoke" / "SHIPPED-FIRST.txt"
TOKEN = "UNWOKE-SHIPPED-FIRST"
START = "<!-- feats-generated:start -->"
END = "<!-- feats-generated:end -->"
CTX = ssl.create_default_context()
OURS = "https://github.com/SeRgi270710267/unwoke-secureblue"
UA = "unwoke-stock-feats"


def esc(s: str) -> str:
    return html.escape(s or "", quote=True)


def display_title(title: str, number: int) -> str:
    """[FEAT] is their request prefix, not a shipped feature."""
    t = (title or "").strip()
    t = re.sub(r"^\[(FEAT|FEATURE|ENHANCEMENT)\]\s*", "", t, flags=re.I)
    return t or f"#{number}"


def token() -> str:
    return os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN") or ""


def fetch_json(url: str) -> object | None:
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": UA,
            **({"Authorization": f"Bearer {token()}"} if token() else {}),
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30, context=CTX) as resp:
            return json.load(resp)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
        print(f"stock-feats: skip {url} ({exc})", flush=True)
        return None


def fetch_issue(repo: str, number: int) -> dict | None:
    data = fetch_json(f"https://api.github.com/repos/{repo}/issues/{number}")
    return data if isinstance(data, dict) else None


def fetch_timeline(repo: str, number: int) -> list[dict]:
    data = fetch_json(
        f"https://api.github.com/repos/{repo}/issues/{number}/timeline?per_page=100"
    )
    if not isinstance(data, list):
        return []
    return [x for x in data if isinstance(x, dict)]


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


def closing_pr(timeline: list[dict]) -> dict:
    """Best merged/closed PR GitHub tied to this issue."""
    found: list[dict] = []
    for ev in timeline:
        src = ((ev.get("source") or {}).get("issue") or {})
        pr = src.get("pull_request") or {}
        if not pr:
            continue
        url = src.get("html_url") or pr.get("html_url") or pr.get("url") or ""
        if not url:
            continue
        merged = bool(pr.get("merged_at"))
        found.append(
            {
                "url": url,
                "title": src.get("title") or "",
                "merged": merged,
                "at": (pr.get("merged_at") or src.get("closed_at") or ev.get("created_at") or "")[:10],
            }
        )
    if not found:
        return {}
    merged_ones = [p for p in found if p.get("merged")]
    return (merged_ones or found)[-1]


def merge(item: dict, live: dict | None, timeline: list[dict]) -> dict:
    out = dict(item)
    if live:
        if live.get("title"):
            out["title"] = live["title"]
        if live.get("html_url"):
            out["url"] = live["html_url"]
        if live.get("state"):
            out["state"] = live["state"]
        if live.get("state_reason"):
            out["state_reason"] = live["state_reason"]
        created = live.get("created_at") or ""
        if created:
            out["created"] = created[:10]
        closed = live.get("closed_at") or ""
        out["closed"] = closed[:10] if closed else ""
    else:
        out.setdefault("state", "open")
        out.setdefault("closed", "")
    pr = closing_pr(timeline)
    if pr:
        out["stock_pr"] = pr.get("url") or ""
        out["stock_pr_at"] = pr.get("at") or ""
        out["stock_pr_title"] = pr.get("title") or ""
    return out


def kind(item: dict) -> str:
    adopted = item.get("adopted") if isinstance(item.get("adopted"), dict) else {}
    if adopted.get("on"):
        return "adopted"
    state = (item.get("state") or "open").lower()
    reason = (item.get("state_reason") or "").lower()
    shipped = parse_day(item.get("shipped") or "")
    closed = parse_day(item.get("closed") or "")
    if state == "open":
        return "ahead"
    if reason in ("not_planned",):
        return "declined"
    if shipped and closed and closed < shipped:
        return "before"
    return "after"


def needs_review(item: dict) -> bool:
    if kind(item) != "after":
        return False
    if item.get("stock_reviewed") == "keep":
        return False
    adopted = item.get("adopted") if isinstance(item.get("adopted"), dict) else {}
    return not adopted.get("on")


def revert_html(revert: str) -> str:
    if not revert:
        return ""
    inner = (
        f"<code>{esc(revert)}</code>"
        if revert.lower().startswith("ujust") or revert.lower().startswith("untick")
        else esc(revert)
    )
    return f'<p class="feat-revert"><span>Revert</span> {inner}</p>'


def card(item: dict) -> str:
    k = kind(item)
    created = item.get("created") or "—"
    shipped = item.get("shipped") or "—"
    closed = item.get("closed") or ""
    wait = ""
    cday = parse_day(created)
    sday = parse_day(shipped)
    if cday and sday:
        wait = age_words((sday - cday).days)
    lag = ""
    if sday and parse_day(closed):
        lag = age_words((parse_day(closed) - sday).days)

    if k == "ahead":
        status, klass = "Not shipped on stock", "feat-open"
        race = f"Opened {esc(created)} as a request. We shipped {esc(shipped)}."
        if wait:
            race += f" They had been asking for {esc(wait)}."
        race += " Still open there, so they have not shipped it. This card stays until they do."
    elif k == "after":
        status, klass = "They shipped after us", "feat-after"
        race = f"We shipped {esc(shipped)}. They closed {esc(closed or 'later')}."
        if lag:
            race += f" That was {esc(lag)} after us."
        if needs_review(item):
            race += " Review their patch; copy only if it is better."
        elif item.get("stock_reviewed") == "keep":
            race += " We looked. Our approach stays."
    elif k == "adopted":
        adopted = item.get("adopted") or {}
        status, klass = "We shipped first; later took theirs", "feat-adopted"
        race = (
            f"We shipped {esc(shipped)} first. They closed {esc(closed or 'later')}. "
            f"On {esc(adopted.get('on') or '')} we took their approach: {esc(adopted.get('note') or '')}"
        )
    elif k == "declined":
        status, klass = "They declined; we still ship", "feat-declined"
        race = f"We shipped {esc(shipped)}. They closed as not planned {esc(closed or '')}. Our default stays."
    else:
        status, klass = "On stock before us", "feat-declined"
        race = f"They closed {esc(closed)} before we shipped {esc(shipped)}."

    n = int(item["issue"])
    url = item.get("url") or f"https://github.com/secureblue/secureblue/issues/{n}"
    commit = item.get("commit") or ""
    links = [f'<a href="{esc(url)}">Stock #{n}</a>']
    if commit:
        links.append(
            f'<a href="{esc(OURS)}/commit/{esc(commit)}"><code>{esc(commit[:7])}</code></a>'
        )
    pr = item.get("stock_pr") or ""
    if pr:
        links.append(f'<a href="{esc(pr)}">Their PR</a>')
    adopted = item.get("adopted") if isinstance(item.get("adopted"), dict) else {}
    if adopted.get("commit"):
        ac = adopted["commit"]
        links.append(
            f'<a href="{esc(OURS)}/commit/{esc(ac)}">Our later commit <code>{esc(ac[:7])}</code></a>'
        )
    where = item.get("where") or "compared/"
    links.append(f'<a href="{esc(where)}">On Unwoke</a>')
    return (
        f'      <article class="feat-card {klass}">\n'
        f'        <p class="feat-status">{esc(status)}</p>\n'
        f'        <p class="tag">{esc(item.get("tag") or "Stock")}</p>\n'
        f"        <h3>{esc(display_title(item.get('title') or '', n))}</h3>\n"
        f'        <p class="feat-race">{race}</p>\n'
        f"        <p>{esc(item.get('we') or '')}</p>\n"
        f"        {revert_html(item.get('revert') or '')}\n"
        f'        <p class="feat-links">{" · ".join(links)}</p>\n'
        f"      </article>\n"
    )


def section(title: str, anchor: str, intro: str, items: list[dict], empty: str) -> str:
    if not items:
        return (
            f'    <h2 id="{esc(anchor)}"><a href="#{esc(anchor)}">{esc(title)}</a></h2>\n'
            f"    <p>{esc(intro)}</p>\n"
            f'    <p class="feat-empty">{esc(empty)}</p>\n'
        )
    parts = [
        f'    <h2 id="{esc(anchor)}"><a href="#{esc(anchor)}">{esc(title)}</a></h2>\n',
        f"    <p>{esc(intro)}</p>\n",
        '    <div class="feat-grid">\n',
    ]
    parts.extend(card(it) for it in items)
    parts.append("    </div>\n")
    return "".join(parts)


def write_ledger(items: list[dict]) -> None:
    """Public, grep-able prior-art file. Lives on the site, in the OS, and on the receipt."""
    lines = [
        TOKEN,
        "Unwoke SecureBlue — not affiliated with secureblue.",
        "MIT License. Copyright (c) 2026 SeRgi270710267.",
        "This file is the public prior-art ledger. Dates are when Unwoke shipped",
        "a reversible default while the official ticket was still a request.",
        "If a later tree copies /usr/share/unwoke or this token, that copy came from here.",
        f"Site: https://sergi270710267.github.io/unwoke-secureblue/ahead/",
        f"Repo: {OURS}",
        f"Written: {dt.datetime.now(dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}",
        "",
        "issue  shipped     state   title",
    ]
    for it in sorted(items, key=lambda x: int(x["issue"])):
        n = int(it["issue"])
        title = (it.get("title") or "").replace("\t", " ")[:80]
        lines.append(
            f"#{n:<6} {it.get('shipped') or '—':<10} {(it.get('state') or 'open'):<7} {title}"
        )
        lines.append(f"         {it.get('url') or f'https://github.com/secureblue/secureblue/issues/{n}'}")
    text = "\n".join(lines) + "\n"
    for path in (LEDGER_DOCS, LEDGER_IMG):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8", newline="\n")
        print(f"wrote {path.relative_to(ROOT)}")


def catch_up_text(items: list[dict]) -> str:
    pending = [it for it in items if needs_review(it)]
    if not pending:
        return ""
    lines = [
        "Stock closed these AFTER we already shipped them. Review their patch.",
        "Do **not** auto-copy. If theirs is better, add `adopted.on` + `adopted.note` + `adopted.commit` in `docs/_tools/stock-feats.json`.",
        "If ours stays, set `stock_reviewed` to `keep` on that item.",
        "",
    ]
    for it in pending:
        n = it["issue"]
        line = f"- #{n} closed {it.get('closed') or '?'} (we shipped {it.get('shipped')})"
        if it.get("stock_pr"):
            line += f" — {it['stock_pr']}"
        else:
            line += f" — {it.get('url') or f'https://github.com/secureblue/secureblue/issues/{n}'}"
        lines.append(line)
    return "\n".join(lines) + "\n"


def main() -> int:
    cfg = json.loads(SRC.read_text(encoding="utf-8"))
    repo = cfg.get("repo") or "secureblue/secureblue"
    items: list[dict] = []
    for raw in cfg.get("items") or []:
        n = int(raw["issue"])
        live = fetch_issue(repo, n)
        timeline = fetch_timeline(repo, n) if live and (live.get("state") or "") != "open" else []
        items.append(merge(raw, live, timeline))

    ahead = [it for it in items if kind(it) == "ahead"]
    after = [it for it in items if kind(it) == "after"]
    adopted = [it for it in items if kind(it) == "adopted"]
    declined = [it for it in items if kind(it) in ("declined", "before")]
    ahead.sort(key=lambda it: parse_day(it.get("created") or "") or dt.date.max)
    after.sort(key=lambda it: parse_day(it.get("closed") or "") or dt.date.max)

    today = dt.date.today()
    waits = []
    for it in ahead:
        created = parse_day(it.get("created") or "")
        if created:
            waits.append((today - created).days)
    oldest = age_words(max(waits)) if waits else "—"

    block = (
        section(
            "Still ahead of stock",
            "ahead",
            "Open [FEAT] tickets on their GitHub. That means requested, not shipped. Defaults here until they close the ticket.",
            ahead,
            "None yet — we would have no open tickets left to beat them on.",
        )
        + section(
            "They shipped after us",
            "after",
            "They closed the ticket after our ship date. The card stays. Review their PR; copy only if it is better.",
            after,
            "None yet. When they close a ticket we already shipped, the factory moves it here automatically and opens a review issue. Tickets are never dropped.",
        )
        + section(
            "We shipped first, then took their approach",
            "adopted",
            "Human decision after review. We were first. We later copied their better patch and say so here.",
            adopted,
            "None yet. If you copy their better patch, set adopted.on / note / commit in stock-feats.json. The factory will not copy it for you.",
        )
        + (
            section(
                "They declined; we still ship",
                "declined",
                "They closed as not planned. Our default stays.",
                declined,
                "None yet.",
            )
            if declined
            else ""
        )
    )

    page = TEMPLATE.read_text(encoding="utf-8")
    page = page.replace("__AHEAD_N__", str(len(ahead)))
    page = page.replace("__AFTER_N__", str(len(after)))
    page = page.replace("__SHIP_N__", str(len(items)))
    page = page.replace("__OLDEST__", esc(oldest))
    # old placeholders still in some snapshots
    page = page.replace("__OPEN_N__", str(len(ahead)))
    if START in page and END in page:
        pre, rest = page.split(START, 1)
        _, post = rest.split(END, 1)
        page = pre + START + "\n" + block + END + post
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(page, encoding="utf-8", newline="\n")

    write_ledger(items)
    extra = catch_up_text(items)
    if extra:
        CATCH.write_text(extra, encoding="utf-8", newline="\n")
        print(f"catch-up {sum(1 for it in items if needs_review(it))} ticket(s)")
    elif CATCH.exists():
        CATCH.write_text("", encoding="utf-8")
    print(
        f"wrote {OUT.relative_to(ROOT)} "
        f"ahead={len(ahead)} after={len(after)} adopted={len(adopted)} declined={len(declined)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
