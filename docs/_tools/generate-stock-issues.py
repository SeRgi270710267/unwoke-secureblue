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
SENSITIVE = re.compile(
    r"(?i)(\b(password|secret|credential|token|private[ _-]?key|api[ _-]?key)\b"
    r"|gh[pousr]_[A-Za-z0-9_]{20,}|BEGIN [A-Z ]*PRIVATE KEY)"
)
MAX_AI = 10


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
    if re.search(r"\b(arm64|aarch64|arm images)\b", text):
        return True
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
        ids = list(dict.fromkeys(in_title))
        # Specific Trivalent packs beat the generic diagnostic.
        if "trivalent" in ids and any(x in ids for x in ("jit", "webgl", "devices")):
            ids = [x for x in ids if x != "trivalent"]
        return ids
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


def ai_conf() -> tuple[str, str, str]:
    """Prefer a paid/free key you own. Else Pollinations text API (no key, public)."""
    key = (
        os.environ.get("UNWOKE_AI_KEY")
        or os.environ.get("GROQ_API_KEY")
        or os.environ.get("XAI_API_KEY")
        or ""
    ).strip()
    if os.environ.get("UNWOKE_AI_BASE"):
        base = os.environ["UNWOKE_AI_BASE"].rstrip("/")
        model = os.environ.get("UNWOKE_AI_MODEL") or "openai"
        return key, base, model
    if os.environ.get("XAI_API_KEY") and not os.environ.get("GROQ_API_KEY"):
        return key, "https://api.x.ai/v1", os.environ.get("UNWOKE_AI_MODEL") or "grok-4-fast-non-reasoning"
    if os.environ.get("GROQ_API_KEY") or os.environ.get("UNWOKE_AI_KEY"):
        return key, "https://api.groq.com/openai/v1", os.environ.get("UNWOKE_AI_MODEL") or "llama-3.3-70b-versatile"
    # Default: no secret. Public Pollinations chat (model id "openai").
    return "", "https://text.pollinations.ai", os.environ.get("UNWOKE_AI_MODEL") or "openai"


def ai_candidate(issue: dict, hits: list[str]) -> bool:
    t = (issue.get("title") or "").lower()
    if "[bug]" in t:
        return True
    return any(
        w in t
        for w in (
            "trivalent",
            "bluetooth",
            "flatpak",
            "webcam",
            "vpn",
            "toolbox",
            "distrobox",
            "nvidia",
            "xwayland",
        )
    )


def ai_batch(
    items: list[dict],
    allowed: list[str],
    key: str,
    base: str,
    model: str,
) -> dict[int, tuple[list[str], str]]:
    """One request per Pages deploy. ids must stay inside the allowlist."""
    payload_issues = []
    for it in items[:MAX_AI]:
        blob = f"{it.get('title') or ''}\n{it.get('body') or ''}"
        if SENSITIVE.search(blob):
            continue
        payload_issues.append(
            {
                "n": it["number"],
                "title": (it.get("title") or "")[:180],
                "body": excerpt(it.get("body") or "")[:360],
                "hint": it.get("hint") or [],
            }
        )
    if not payload_issues:
        return {}
    sys_msg = (
        "You help Unwoke SecureBlue (overlay on secureblue Silverblue/Kinoite). "
        "Return JSON only: {\"out\":[{\"n\":1,\"ids\":[\"jit\"],\"answer\":\"two sentences\"}]}. "
        "ids subset of allowed. answer = what to try on Unwoke, revertable ujust only. "
        "If stock kernel/browser with no overlay knob, ids [] and answer says wait for their signed image. "
        "Never setenforce 0, unsigned rebase, gpgcheck=0, new shell, Bubblejail Trivalent."
    )
    user_msg = json.dumps({"allowed": allowed, "issues": payload_issues})
    raw = json.dumps(
        {
            "model": model,
            "temperature": 0,
            "max_tokens": 900,
            "messages": [
                {"role": "system", "content": sys_msg},
                {"role": "user", "content": user_msg},
            ],
        }
    ).encode("utf-8")
    headers = {
        "Content-Type": "application/json",
        "User-Agent": "unwoke-stock-issues",
    }
    if key:
        headers["Authorization"] = f"Bearer {key}"
    chat = f"{base}/chat/completions" if base.endswith("/v1") else f"{base}/openai"
    text = ""
    try:
        req = urllib.request.Request(chat, data=raw, method="POST", headers=headers)
        with urllib.request.urlopen(req, timeout=45, context=CTX) as resp:
            data = json.load(resp)
        if isinstance(data, dict):
            text = (((data.get("choices") or [{}])[0].get("message") or {}).get("content")) or ""
        else:
            text = str(data)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, KeyError, IndexError) as exc:
        print(f"stock-issues: AI POST skip ({exc})", file=sys.stderr)
        if key:
            return {}
        # Public GET is what still works without pollen/credits.
        short = (
            "JSON only {\"out\":[{\"n\":0,\"ids\":[],\"answer\":\"\"}]}. "
            "Unwoke overlay. ids subset of: " + ",".join(allowed) + ". Issues: "
            + " | ".join(f"#{x['n']} {x['title']}" for x in payload_issues)
        )
        get_url = "https://text.pollinations.ai/" + urllib.request.quote(short[:1500])
        try:
            greq = urllib.request.Request(get_url, headers={"User-Agent": "unwoke-stock-issues"})
            with urllib.request.urlopen(greq, timeout=40, context=CTX) as resp:
                text = resp.read().decode("utf-8", errors="replace")
        except (urllib.error.URLError, TimeoutError) as exc2:
            print(f"stock-issues: AI GET skip ({exc2})", file=sys.stderr)
            return {}
    m = re.search(r"\{.*\}", text, re.S)
    if not m:
        return {}
    try:
        parsed = json.loads(m.group(0))
    except json.JSONDecodeError:
        return {}
    allow = set(allowed)
    out: dict[int, tuple[list[str], str]] = {}
    for row in parsed.get("out") or []:
        try:
            n = int(row.get("n"))
        except (TypeError, ValueError):
            continue
        ids = []
        for x in row.get("ids") or []:
            s = str(x)
            if s in allow and s not in ids:
                ids.append(s)
        answer = re.sub(r"\s+", " ", str(row.get("answer") or "")).strip()
        if FORBIDDEN.search(answer):
            answer = ""
        if len(answer) > 400:
            answer = answer[:397] + "…"
        out[n] = (ids, answer)
    return out


def render_fix(fid: str, spec: dict) -> str:
    code = html.escape(spec.get("code") or "")
    revert = html.escape(spec.get("revert") or "")
    note = html.escape(spec.get("note") or "")
    return (
        f'<div class="cmd-box">'
        f'<p class="cmd-label">Type this <span>(revertable · not baked)</span></p>'
        f"<pre><code>{code}</code></pre>"
        f'<p class="cmd-off">Turn it back off: <code>{revert}</code></p>'
        f"<p>{note}</p></div>"
    )


def render_item(issue: dict, fix_ids: list[str], fixes: dict, answer: str = "") -> str:
    num = issue.get("number")
    title = html.escape(issue.get("title") or f"#{num}")
    url = html.escape(issue.get("html_url") or "", quote=True)
    when = html.escape((issue.get("updated_at") or "")[:10])
    blurb = html.escape(excerpt(issue.get("body") or ""))
    boxes = "\n".join(render_fix(fid, fixes[fid]) for fid in fix_ids if fid in fixes)
    if answer:
        kind = "has-ai"
        badge = '<span class="badge badge-ai">AI note</span>'
        ai_html = (
            f'<div class="ai-panel" id="ai-{html.escape(str(num))}">'
            f'<p class="ai-kicker">AI note · Unwoke only</p>'
            f"<p>{html.escape(answer)}</p>"
            f"<p class=\"ai-foot\">Guess from the issue title. Not a patch. Commands below are the allowlist.</p>"
            f"</div>"
        )
    else:
        kind = "no-ai"
        badge = '<span class="badge badge-map">Keyword only</span>'
        ai_html = (
            f'<div class="ai-panel missing" id="ai-{html.escape(str(num))}">'
            f'<p class="ai-kicker">No AI note this deploy</p>'
            f"<p>The free model skipped or rate-limited. The box below is still the overlay command we map to this issue.</p>"
            f"</div>"
        )
    return (
        f'<article class="card issue-card {kind}">'
        f'<p class="eyebrow">#{html.escape(str(num))} · {when} {badge}</p>'
        f'<h2><a href="{url}">{title}</a></h2>'
        f"{ai_html}"
        f"{boxes}"
        f"{f'<p class="stock-blurb">{blurb}</p>' if blurb else ''}"
        f'<p class="mirror-meta"><a href="{url}">Stock issue #{html.escape(str(num))}</a></p>'
        f"</article>"
    )


def main() -> int:
    cfg = json.loads(MAP.read_text(encoding="utf-8"))
    fixes = cfg.get("fixes") or {}
    rows: list[str] = []
    kept = 0
    scanned = 0
    ai_n = 0
    key, base, model = ai_conf()
    allowed = list(fixes.keys())
    print(f"stock-issues: AI {model} @ {base}" + (" (keyed)" if key else " (public Pollinations, one batch)"))
    pending: list[dict] = []
    for issue in load_issues():
        scanned += 1
        if skip(issue, cfg):
            continue
        hits = match_fixes(issue, cfg)
        if hits or ai_candidate(issue, hits):
            rec = dict(issue)
            rec["hint"] = hits
            rec["_hits"] = hits
            pending.append(rec)
    ai_map: dict[int, tuple[list[str], str]] = {}
    if base and pending:
        ai_map = ai_batch(pending, allowed, key, base, model)
        print(f"stock-issues: AI returned {len(ai_map)} notes")
    for rec in pending:
        hits = list(rec.get("_hits") or [])
        extra, answer = ai_map.get(int(rec.get("number") or 0), ([], ""))
        if extra:
            hits = list(dict.fromkeys(hits + extra))
        if not hits:
            continue
        rows.append(render_item(rec, hits, fixes, answer))
        kept += 1
        if answer:
            ai_n += 1
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
        .replace("__AI_N__", str(ai_n))
    )
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(html_out, encoding="utf-8")
    print(f"stock-issues: {kept} shown / {scanned} scanned / {len(ai_map)} AI notes -> {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
