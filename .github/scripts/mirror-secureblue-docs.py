#!/usr/bin/env python3
"""Fetch stock secureblue.dev markdown and wrap it in our chrome.

Writes only under docs/secureblue/. Never touches docs/faq, docs/features, etc.
"""
from __future__ import annotations

import datetime as dt
import html
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

try:
    import markdown as md_lib
except ImportError:
    sys.exit("install markdown: python3 -m pip install markdown")

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs" / "secureblue"
TEMPLATE = Path(__file__).with_name("mirror-template.html").read_text(encoding="utf-8")
UA = "Unwoke-SecureBlue-mirror (https://github.com/SeRgi270710267/unwoke-secureblue)"
API = "https://api.github.com/repos/secureblue/secureblue.dev/contents"
RAW = "https://raw.githubusercontent.com/secureblue/secureblue.dev/live"
SKIP = {
    "INDEX.md",
    "CODE_OF_CONDUCT.md",
    "404.md",
}

DONATE_NOTICE = """
<p class="alert caution"><strong>This money goes to secureblue. Not Unwoke SecureBlue.</strong> Open Collective, GitHub Sponsors, Monero, Coinbase — all theirs. We do not take donations and never will. <a href="donate/">Our donate page</a> exists to say that.</p>
"""

POSTINSTALL_NOTICE = """
<p class="alert note"><strong>Stock secureblue post-install.</strong> After Unwoke USB or rebase you still do most of this (their Secure Boot key, kargs, <code>ujust audit-secureblue</code>, USBGuard). Overlay extras: <a href="post-install/">our Post-install</a>. Canonical: <a href="https://secureblue.dev/post-install">secureblue.dev/post-install</a>.</p>
"""

CONTRIBUTING_NOTICE = """
<p class="alert caution"><strong>This is how you contribute to <em>secureblue</em>, not Unwoke SecureBlue.</strong> PRs against their repo, their AI ban, their Discord, their Covenant — all them. Overlay bugs and patches go to <a href="https://github.com/SeRgi270710267/unwoke-secureblue">our GitHub</a>. We do not use their CoC; see <a href="conduct/">Conduct</a>.</p>
"""

INSTALL_NOTICE = """
<p class="alert caution"><strong>This is how you install stock secureblue.</strong> Unwoke is a different GHCR image. Empty disk: <a href="install/">our USB ISO or rebase</a>. Their interactive ISO picker (GNOME/KDE/Sway × NVIDIA, torrents) stays on <a href="https://secureblue.dev/install">secureblue.dev/install</a> — we do not run their download form here.</p>
"""

FAQ_NOTICE = """
<p class="alert note"><strong>Stock FAQ.</strong> They still have Bazaar, verified Flathub, Homebrew, and <code>ujust install-vpn</code> / <code>install-steam</code>. Overlay deltas (no store, extra locks, Proton/IVPN/Mullvad wizards): <a href="faq/">our FAQ</a> and <a href="compared/">Compared</a>.</p>
"""

FEATURES_NOTICE = """
<p class="alert note"><strong>Stock feature list.</strong> Kernel, SELinux, Trivalent, USBGuard — inherited. What this overlay adds or changes: <a href="features/">our Features</a>.</p>
"""

IMAGES_NOTICE = """
<p class="alert caution"><strong>Stock image catalog.</strong> Sway, COSMIC, CoreOS, IoT, closed NVIDIA — they ship those. Unwoke only overlays Silverblue/Kinoite × nvidia-open × Origin/Trivalent/browserless. Our names: <a href="images/">Images</a>.</p>
"""

VERIFICATION_NOTICE = """
<p class="alert note"><strong>Stock ISO verification.</strong> For an Unwoke USB, verify our <code>cosign.pub</code> and <code>SHA256SUMS</code> as on <a href="install/">Install</a>. This page is how you check <em>their</em> installer media.</p>
"""

REPORTING_NOTICE = """
<p class="alert note"><strong>Stock security reporting.</strong> Overlay bugs and patches: <a href="https://github.com/SeRgi270710267/unwoke-secureblue">our GitHub</a>. Vulnerabilities in their kernel/Trivalent go to them.</p>
"""

PAGE_NOTICES = {
    "/donate": DONATE_NOTICE,
    "/post-install": POSTINSTALL_NOTICE,
    "/contributing": CONTRIBUTING_NOTICE,
    "/install": INSTALL_NOTICE,
    "/faq": FAQ_NOTICE,
    "/features": FEATURES_NOTICE,
    "/images": IMAGES_NOTICE,
    "/verification": VERIFICATION_NOTICE,
    "/reporting": REPORTING_NOTICE,
}

HUB_GROUPS = (
    ("Install and after", ("/install", "/post-install", "/verification")),
    ("What they ship", ("/features", "/faq", "/images")),
    ("Project", ("/contributing", "/donate", "/reporting")),
)

INCLUDE_RE = re.compile(
    r"\{%\s*include\s+alert\.html\s+type=(['\"])([^'\"]+)\1\s+content=(['\"])((?:\\.|.)*?)\3\s*%\}",
    re.I | re.S,
)
FORM_RE = re.compile(r"<form\b.*?</form>", re.I | re.S)
KRAMDOWN_ATTR = re.compile(r"\{:\s*([^}]+)\}")
FRONT_RE = re.compile(r"^---\n(.*?)\n---\n", re.S)
STOCK_HOST = "https://secureblue.dev"


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(req, timeout=45) as resp:
        return resp.read()


def list_markdown() -> list[dict]:
    files = []
    for folder in ("content", "content/articles"):
        data = json.loads(fetch(f"{API}/{folder}?ref=live"))
        if not isinstance(data, list):
            raise RuntimeError(f"unexpected listing for {folder}")
        for item in data:
            if item.get("type") == "file" and item.get("name", "").endswith(".md"):
                if item["name"] in SKIP:
                    continue
                files.append(item)
    return files


def parse_front(text: str) -> tuple[dict, str]:
    meta: dict[str, str] = {}
    m = FRONT_RE.match(text)
    if not m:
        return meta, text
    for line in m.group(1).splitlines():
        if ":" not in line:
            continue
        k, v = line.split(":", 1)
        meta[k.strip()] = v.strip().strip('"').strip("'")
    return meta, text[m.end() :]


def alerts_to_html(text: str) -> str:
    def repl(m: re.Match[str]) -> str:
        kind = html.escape(m.group(2).lower(), quote=True)
        raw = m.group(4).replace("\\'", "'").replace('\\"', '"').replace("<br>", "\n")
        body = html.escape(raw, quote=False).replace("\n", "<br>\n")
        return f"\n\n<div class=\"alert {kind}\"><p>{body}</p></div>\n\n"

    return INCLUDE_RE.sub(repl, text)


def replace_stock_forms(fragment: str) -> str:
    """Do not execute their ISO picker. Point at their site and ours."""
    box = (
        '<div class="alert note"><p><strong>Stock ISO downloader</strong> is an interactive '
        "form on <a href=\"https://secureblue.dev/install\">secureblue.dev/install</a> "
        "(GNOME/KDE/Sway × NVIDIA, torrents, checksums). We do not run their form here. "
        "Unwoke USB or rebase: <a href=\"install/\">our Install</a>.</p></div>"
    )
    return FORM_RE.sub(box, fragment)


def wrap_tables(fragment: str) -> str:
    fragment = re.sub(r"<table\b", '<div class="table-container"><table', fragment, flags=re.I)
    fragment = re.sub(r"</table>", "</table></div>", fragment, flags=re.I)
    return fragment


CMDS_JSON = ROOT / "docs" / "_tools" / "stock-unwoke-cmds.json"
JUST = ROOT / "files" / "justfiles" / "unwoke.just"
UJUST_NAME = re.compile(r"ujust\s+([a-z][a-z0-9-]*)", re.I)
RISKY_UJUST = re.compile(r"^(set|toggle|install|rebase)-")
RECIPE_NAME = re.compile(r"^([a-z][a-z0-9-]*)(?:\s+\*args)?:", re.M)

PRE_BLOCK = re.compile(r"<pre\b[^>]*>.*?</pre>", re.I | re.S)
P_BLOCK = re.compile(r"<p\b[^>]*>.*?</p>", re.I | re.S)


def load_unwoke_recipes() -> set[str]:
    if not JUST.is_file():
        return set()
    return set(RECIPE_NAME.findall(JUST.read_text(encoding="utf-8")))


def load_cmd_book() -> tuple[list[dict[str, object]], set[str]]:
    data = json.loads(CMDS_JSON.read_text(encoding="utf-8"))
    cmds: list[dict[str, object]] = []
    for raw in data.get("cmds") or []:
        spec = dict(raw)
        needles = spec.get("needles") or []
        spec["needles"] = tuple(str(n) for n in needles)
        more = spec.get("more")
        if isinstance(more, list) and len(more) == 2:
            spec["more"] = (str(more[0]), str(more[1]))
        cmds.append(spec)
    same = {str(x) for x in (data.get("same") or [])}
    return cmds, same


def discover_ujust(text: str) -> set[str]:
    return {m.group(1).lower() for m in UJUST_NAME.finditer(text)}


def pair_recipe(stock_cmd: str, recipes: set[str]) -> str | None:
    if stock_cmd in recipes:
        return stock_cmd
    for suf in ("-modules", "-unfiltered", "-unverified", "-secureblue"):
        if stock_cmd.endswith(suf):
            cand = stock_cmd[: -len(suf)]
            if cand in recipes:
                return cand
            if cand.startswith("set-") and cand in recipes:
                return cand
    return None


def extra_specs_for_page(
    page_text: str,
    book: list[dict[str, object]],
    same: set[str],
    recipes: set[str],
    unmatched: list[str],
    auto_ids: list[str],
) -> list[dict[str, object]]:
    covered: set[str] = set(same)
    for spec in book:
        for n in spec.get("needles") or ():
            covered.update(discover_ujust(str(n)))
    extra: list[dict[str, object]] = []
    for cmd in sorted(discover_ujust(page_text)):
        if cmd in covered:
            continue
        pair = pair_recipe(cmd, recipes)
        if pair and pair != cmd:
            extra.append(
                {
                    "id": f"auto-{cmd}",
                    "needles": (f"ujust {cmd}",),
                    "code": f"ujust {pair} on",
                    "note": "Auto-paired from the overlay justfile "
                    f"(<code>{html.escape(cmd)}</code> → <code>{html.escape(pair)}</code>). "
                    "Default may be off. Does not auto-unlock. If the pairing is wrong, add a "
                    "stanza to <code>docs/_tools/stock-unwoke-cmds.json</code>.",
                    "more": ("faq/", "Our FAQ"),
                }
            )
            auto_ids.append(f"{cmd}->{pair}")
            continue
        if RISKY_UJUST.match(cmd):
            extra.append(
                {
                    "id": f"unknown-{cmd}",
                    "needles": (f"ujust {cmd}",),
                    "code": "ujust why\nujust setup",
                    "note": "New stock command with no Unwoke mapping yet. Overlay defaults may "
                    "already be stricter. Do not assume their on/off direction. A factory issue "
                    "stays open until <code>stock-unwoke-cmds.json</code> gets a real stanza.",
                    "more": ("tutorials/", "Tutorials"),
                }
            )
            if cmd not in unmatched:
                unmatched.append(cmd)
    return extra


def _unwoke_box(spec: dict[str, object]) -> str:
    sid = html.escape(str(spec["id"]), quote=True)
    code = html.escape(str(spec["code"]))
    note = str(spec["note"])
    more = spec.get("more")
    extra = ""
    if isinstance(more, (tuple, list)) and len(more) == 2:
        extra = (
            f' <a href="{html.escape(str(more[0]), quote=True)}">{html.escape(str(more[1]))}</a>.'
        )
    return (
        f'<div class="alert note unwoke-cmd" data-unwoke-cmd="{sid}">'
        "<p><strong>On Unwoke SecureBlue</strong> — the stock snippet above is theirs. "
        f"Use this as well or instead:</p>"
        f"<pre><code>{code}</code></pre>"
        f"<p>{note}{extra}</p></div>"
    )


def _contains(hay: str, needles: tuple[str, ...]) -> bool:
    low = hay.lower()
    return any(n.lower() in low for n in needles)


def annotate_unwoke_commands(fragment: str, specs: list[dict[str, object]]) -> str:
    """Under stock commands that differ here, add the Unwoke ujust. Idempotent."""
    for spec in specs:
        sid = str(spec["id"])
        if f'data-unwoke-cmd="{sid}"' in fragment:
            continue
        needles = spec["needles"]
        if not isinstance(needles, tuple):
            continue
        box = _unwoke_box(spec)
        inserted = False

        def put_pre(m: re.Match[str], box: str = box, needles: tuple[str, ...] = needles) -> str:
            nonlocal inserted
            block = m.group(0)
            if inserted or not _contains(block, needles):
                return block
            inserted = True
            return block + box

        fragment = PRE_BLOCK.sub(put_pre, fragment)
        if inserted:
            continue

        def put_p(m: re.Match[str], box: str = box, needles: tuple[str, ...] = needles) -> str:
            nonlocal inserted
            block = m.group(0)
            if inserted or not _contains(block, needles):
                return block
            inserted = True
            return block + box

        fragment = P_BLOCK.sub(put_p, fragment)
        if inserted:
            continue
        low = fragment.lower()
        pos = -1
        for n in needles:
            i = low.find(n.lower())
            if i != -1 and (pos == -1 or i < pos):
                pos = i
        if pos < 0:
            continue
        rest = fragment[pos:]
        cut = -1
        for tag in ("</pre>", "</li>", "</p>", "</h4>", "</h3>", "</h2>"):
            j = rest.lower().find(tag)
            if j != -1 and (cut == -1 or j < cut):
                cut = j + len(tag)
        if cut == -1:
            continue
        at = pos + cut
        fragment = fragment[:at] + box + fragment[at:]
    return fragment


def keep_heading_ids(text: str) -> str:
    """Put kramdown {: #id} on the heading line so attr_list consumes it; drop leftovers."""
    text = re.sub(
        r"^(#{1,6}[^\n]+)\n(?:[ \t]*\n)*\{:\s*#([A-Za-z0-9_-]+)\s*\}[ \t]*$",
        r"\1 {: #\2}",
        text,
        flags=re.M,
    )
    text = re.sub(r"\n\{:\s*[^}\n]+\}[ \t]*", "\n", text)
    return text


HEADING_RE = re.compile(r"<h([23])\b([^>]*)>(.*?)</h\1>", re.I | re.S)


def _plain(inner: str) -> str:
    t = re.sub(r"<[^>]+>", "", inner)
    t = html.unescape(t)
    return re.sub(r"\s+", " ", t).strip()


def _hid(attrs: str, inner: str) -> str:
    m = re.search(r'\bid="([^"]+)"', attrs)
    if m:
        return m.group(1)
    m = re.search(r'href="[^"]*#([^"]+)"', inner)
    if m:
        return m.group(1)
    return ""


def rebuild_toc(fragment: str, here: str) -> str:
    """Replace stock's messy markdown TOC with grouped cards from real h2/h3."""
    matches = list(HEADING_RE.finditer(fragment))
    toc_at: int | None = None
    content_at: int | None = None
    groups: list[dict[str, object]] = []
    current: dict[str, object] | None = None
    for m in matches:
        level = int(m.group(1))
        title = _plain(m.group(3))
        hid = _hid(m.group(2), m.group(3))
        if level == 2 and re.search(r"table of contents", title, re.I):
            toc_at = m.start()
            continue
        if toc_at is None:
            continue
        if not hid:
            continue
        if level == 2:
            if content_at is None:
                content_at = m.start()
            current = {"id": hid, "title": title, "items": []}
            groups.append(current)
        elif level == 3 and current is not None:
            items = current["items"]
            if isinstance(items, list):
                items.append((hid, title))
    if toc_at is None or content_at is None or not groups:
        return fragment
    cols: list[str] = []
    for g in groups:
        gid = html.escape(str(g["id"]), quote=True)
        gtitle = html.escape(str(g["title"]))
        lis = []
        for hid, title in g["items"] if isinstance(g["items"], list) else []:
            lis.append(
                f'<li><a href="{html.escape(here, quote=True)}#{html.escape(hid, quote=True)}">'
                f"{html.escape(str(title))}</a></li>"
            )
        inner = f"<ul>{''.join(lis)}</ul>" if lis else ""
        cols.append(
            f'<div class="toc-group"><h3><a href="{html.escape(here, quote=True)}#{gid}">'
            f"{gtitle}</a></h3>{inner}</div>"
        )
    nav = (
        '<nav class="mirror-toc" aria-label="On this page">'
        "<p class=\"eyebrow\">On this page</p>"
        f'<div class="toc-grid">{"".join(cols)}</div></nav>\n'
    )
    return fragment[:toc_at] + nav + fragment[content_at:]


def polish_mirror_html(fragment: str, here: str) -> str:
    fragment = re.sub(r"<p>\s*\{:[^}]*\}\s*</p>", "", fragment, flags=re.I | re.S)
    fragment = re.sub(r"\{:\s*#[A-Za-z0-9_-]+\s*\}", "", fragment)
    fragment = rebuild_toc(fragment, here)
    return fragment


def pretty_title(title: str) -> str:
    t = re.sub(r"\s*\|\s*secureblue\s*$", "", title, flags=re.I).strip()
    return t or title


SUBNAV = (
    ("secureblue/", "Index"),
    ("secureblue/install/", "Install"),
    ("secureblue/post-install/", "Post-install"),
    ("secureblue/faq/", "FAQ"),
    ("secureblue/features/", "Features"),
    ("secureblue/images/", "Images"),
    ("secureblue/articles/", "Articles"),
)


def subnav_html(here: str) -> str:
    bits = []
    for href, label in SUBNAV:
        current = False
        if href == "secureblue/":
            current = here.rstrip("/") == "secureblue"
        elif here.startswith(href.rstrip("/")):
            current = True
        cur = ' aria-current="page"' if current else ""
        bits.append(
            f'<a href="{html.escape(href, quote=True)}"{cur}>{html.escape(label)}</a>'
        )
    return '<nav class="mirror-subnav" aria-label="Stock docs">' + "".join(bits) + "</nav>"


_UNSAFE_HTML = re.compile(
    r"<(script|iframe|object|embed|form|link|meta|base)\b[^>]*>.*?</\1\s*>"
    r"|<(script|iframe|object|embed|form|link|meta|base)\b[^>]*/?>"
    r"|\son[a-z]+\s*="
    r"|javascript:"
    r"|data:text/html",
    re.I | re.S,
)


def sanitize_html(fragment: str) -> str:
    """Drop script-like markup from mirrored markdown HTML. Not a full browser sandbox."""
    prev = None
    out = fragment
    while prev != out:
        prev = out
        out = _UNSAFE_HTML.sub("", out)
    return out


def local_for(permalinks: dict[str, str], path: str, frag: str) -> str | None:
    p = path.rstrip("/") or "/"
    if not p.startswith("/"):
        p = "/" + p
    if p not in permalinks:
        return None
    url = permalinks[p]
    return f"{url}#{frag}" if frag else url


def rewrite_html(html: str, permalinks: dict[str, str], here: str) -> str:
    html = html.replace('src="/assets/', f'src="{STOCK_HOST}/assets/')
    html = html.replace("src='/assets/", f"src='{STOCK_HOST}/assets/")

    def slash_href(m: re.Match[str]) -> str:
        q, path = m.group(1), m.group(2)
        if path.startswith("//") or path.startswith("http"):
            return m.group(0)
        p, _, frag = path.partition("#")
        if p.startswith("/assets/"):
            return f"href={q}{STOCK_HOST}{path}{q}"
        mapped = local_for(permalinks, p, frag)
        if mapped:
            return f"href={q}{mapped}{q}"
        if (p.rstrip("/") or "/") == "/":
            return f"href={q}{STOCK_HOST}/{('#' + frag) if frag else ''}{q}"
        return f"href={q}{STOCK_HOST}{path}{q}"

    html = re.sub(r'href=(["\'])(/[^"\']*)\1', slash_href, html)

    def frag_href(m: re.Match[str]) -> str:
        q, frag = m.group(1), m.group(2)
        return f"href={q}{here}#{frag}{q}"

    html = re.sub(r'href=(["\'])#([^"\']*)\1', frag_href, html)

    def abs_href(m: re.Match[str]) -> str:
        q, rest = m.group(1), m.group(2)
        path, _, frag = rest.partition("#")
        mapped = local_for(permalinks, path or "/", frag)
        if mapped:
            return f"href={q}{mapped}{q}"
        return m.group(0)

    html = re.sub(r'href=(["\'])https://secureblue\.dev([^"\']*)\1', abs_href, html)
    return html


def slug_from_name(name: str, folder: str) -> str:
    stem = name[:-3].lower().replace("_", "-")
    if folder.endswith("/articles"):
        return f"/articles/{stem}"
    return f"/{stem}"


def out_dir_for(permalink: str) -> Path:
    rel = permalink.strip("/")
    return OUT / rel


def render_page(
    title: str,
    description: str,
    canonical: str,
    body: str,
    sha: str,
    fetched: str,
    here: str,
) -> str:
    html = TEMPLATE
    html = html.replace("__HERE__", here)
    html = html.replace("__SUBNAV__", subnav_html(here))
    html = html.replace("__TITLE__", title)
    html = html.replace("__DESCRIPTION__", description)
    html = html.replace("__CANONICAL__", canonical)
    html = html.replace("__BODY__", body)
    html = html.replace("__SHA__", sha)
    html = html.replace("__FETCHED__", fetched)
    return html


def main() -> int:
    fetched = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    listing = list_markdown()
    sha = "live"
    try:
        commits = json.loads(
            fetch("https://api.github.com/repos/secureblue/secureblue.dev/commits?path=content&per_page=1")
        )
        if commits:
            sha = commits[0]["sha"][:12]
    except (urllib.error.URLError, KeyError, IndexError, json.JSONDecodeError):
        pass

    pages: list[tuple[str, str, str, str]] = []
    permalinks: dict[str, str] = {}

    for item in listing:
        raw = fetch(item["download_url"]).decode("utf-8")
        meta, body_md = parse_front(raw)
        folder = str(item.get("path", "")).rsplit("/", 1)[0]
        permalink = meta.get("permalink") or slug_from_name(item["name"], folder)
        if item["name"] == "ARTICLES.md":
            permalink = meta.get("permalink") or "/articles"
        if not permalink.startswith("/"):
            permalink = "/" + permalink
        permalinks[permalink.rstrip("/") or "/"] = "secureblue" + permalink.rstrip("/") + "/"
        title = meta.get("title") or item["name"]
        description = meta.get("description") or "Mirrored secureblue documentation."
        pages.append((permalink, title, description, body_md))

    if OUT.exists():
        for old in OUT.rglob("*"):
            if old.is_file():
                old.unlink()

    try:
        book, same = load_cmd_book()
    except (OSError, json.JSONDecodeError) as exc:
        print(f"stock-unwoke-cmds.json: {exc}", file=sys.stderr)
        book, same = [], set()
    recipes = load_unwoke_recipes()
    unmatched: list[str] = []
    auto_ids: list[str] = []

    index_links = []
    for permalink, title, description, body_md in pages:
        body_md = alerts_to_html(body_md)
        body_md = keep_heading_ids(body_md)
        body_html = md_lib.markdown(
            body_md,
            extensions=["extra", "sane_lists", "toc"],
        )
        here = permalinks[permalink.rstrip("/") or "/"]
        body_html = rewrite_html(body_html, permalinks, here)
        body_html = replace_stock_forms(body_html)
        body_html = wrap_tables(body_html)
        body_html = sanitize_html(body_html)
        specs = book + extra_specs_for_page(
            body_md, book, same, recipes, unmatched, auto_ids
        )
        body_html = annotate_unwoke_commands(body_html, specs)
        body_html = polish_mirror_html(body_html, here)
        extra = PAGE_NOTICES.get(permalink.rstrip("/"), "")
        if extra:
            body_html = extra + body_html
        canonical = "https://secureblue.dev" + permalink
        dest = out_dir_for(permalink)
        dest.mkdir(parents=True, exist_ok=True)
        page_title = f"{pretty_title(title)} (mirrored)"
        (dest / "index.html").write_text(
            render_page(page_title, description, canonical, body_html, sha, fetched, here),
            encoding="utf-8",
        )
        index_links.append((permalinks[permalink.rstrip("/") or "/"], title))

    license_txt = fetch(f"{RAW}/LICENSE.txt").decode("utf-8")
    (OUT / "LICENSE-secureblue.dev.txt").write_text(license_txt, encoding="utf-8")

    by_path = {href: title for href, title in index_links}
    sections = []
    used: set[str] = set()
    for label, keys in HUB_GROUPS:
        lis = []
        for key in keys:
            href = "secureblue" + key + "/"
            if href in by_path:
                lis.append(
                    f'<li><a href="{href}">{html.escape(pretty_title(by_path[href]))}</a></li>'
                )
                used.add(href)
        if lis:
            sections.append(
                f'<div class="card"><p class="eyebrow">{html.escape(label)}</p>'
            f"<ul>{''.join(lis)}</ul></div>"
            )
    articles = []
    leftover = []
    for href, title in sorted(index_links, key=lambda x: x[1].lower()):
        if href in used:
            continue
        item = f'<li><a href="{href}">{html.escape(pretty_title(title))}</a></li>'
        if "/articles/" in href:
            articles.append(item)
        else:
            leftover.append(item)
    if articles:
        sections.append(
            '<div class="card"><p class="eyebrow">Articles</p><ul>' + "".join(articles) + "</ul></div>"
        )
    if leftover:
        sections.append(
            '<div class="card"><p class="eyebrow">More</p><ul>' + "".join(leftover) + "</ul></div>"
        )
    index_body = f"""
    <h1>Stock secureblue docs</h1>
    <p>Pulled daily from <a href="https://secureblue.dev">secureblue.dev</a> and wrapped in our chrome. Unwoke FAQ, Features, Images, and Install stay on the main nav — this tree cannot overwrite them.</p>
    <div class="alert note"><p><strong>These pages describe stock.</strong> They still mention Bazaar, verified Flathub, Homebrew, and their ISO picker. Overlay rules: <a href="compared/">Compared</a>. How to install Unwoke: <a href="install/">Install</a>.</p></div>
    <div class="cards docs-index">{"".join(sections)}</div>
    <p>Not mirrored on purpose: their homepage and Contributor Covenant. Canonical for everything here is still <a href="https://secureblue.dev">secureblue.dev</a>.</p>
    """
    (OUT / "index.html").write_text(
        render_page(
            "Stock secureblue docs | Unwoke SecureBlue",
            "Mirrored secureblue.dev documentation. Unwoke pages are separate.",
            "https://secureblue.dev/",
            index_body,
            sha,
            fetched,
            "secureblue/",
        ),
        encoding="utf-8",
    )
    report = {
        "unmatched": sorted(set(unmatched)),
        "auto": auto_ids,
        "mapped": [str(s.get("id")) for s in book],
    }
    (OUT / "unwoke-cmd-report.json").write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8"
    )
    if unmatched:
        print("UNMATCHED stock ujust (add stock-unwoke-cmds.json): " + ", ".join(report["unmatched"]))
    else:
        print("stock ujust footnotes: all mapped or known-same")
    print(f"mirrored {len(pages)} pages from secureblue.dev @{sha} -> {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
