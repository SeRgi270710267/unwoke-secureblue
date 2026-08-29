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
KRAMDOWN_RE = re.compile(r"\{:\s*[^}]+\}")
FRONT_RE = re.compile(r"^---\n(.*?)\n---\n", re.S)


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


def rewrite_html(html: str, permalinks: dict[str, str]) -> str:
    html = html.replace('src="/assets/', 'src="https://secureblue.dev/assets/')
    html = html.replace("src='/assets/", "src='https://secureblue.dev/assets/")

    def href(m: re.Match[str]) -> str:
        q, path = m.group(1), m.group(2)
        if path.startswith("//") or path.startswith("http"):
            return m.group(0)
        p, _, frag = path.partition("#")
        p = p.rstrip("/") or "/"
        if p.startswith("/assets/"):
            url = "https://secureblue.dev" + path
        elif p in permalinks:
            url = permalinks[p]
            if frag:
                url = f"{url}#{frag}"
        elif p == "/":
            url = "https://secureblue.dev/" + (f"#{frag}" if frag else "")
        else:
            url = "https://secureblue.dev" + path
        return f"href={q}{url}{q}"

    return re.sub(r'href=(["\'])(/[^"\']*)\1', href, html)


def slug_from_name(name: str, folder: str) -> str:
    stem = name[:-3].lower().replace("_", "-")
    if folder.endswith("/articles"):
        return f"/articles/{stem}"
    return f"/{stem}"


def out_dir_for(permalink: str) -> Path:
    rel = permalink.strip("/")
    return OUT / rel


def render_page(title: str, description: str, canonical: str, body: str, sha: str, fetched: str) -> str:
    html = TEMPLATE
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

    index_links = []
    for permalink, title, description, body_md in pages:
        body_md = alerts_to_html(body_md)
        body_md = KRAMDOWN_RE.sub("", body_md)
        body_html = md_lib.markdown(
            body_md,
            extensions=["extra", "sane_lists", "toc"],
        )
        body_html = rewrite_html(body_html, permalinks)
        body_html = replace_stock_forms(body_html)
        body_html = wrap_tables(body_html)
        body_html = sanitize_html(body_html)
        extra = PAGE_NOTICES.get(permalink.rstrip("/"), "")
        if extra:
            body_html = extra + body_html
        canonical = "https://secureblue.dev" + permalink
        dest = out_dir_for(permalink)
        dest.mkdir(parents=True, exist_ok=True)
        page_title = f"{title} (mirrored)"
        (dest / "index.html").write_text(
            render_page(page_title, description, canonical, body_html, sha, fetched),
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
                lis.append(f'<li><a href="{href}">{html.escape(by_path[href])}</a></li>')
                used.add(href)
        if lis:
            sections.append(
                f'<div class="card"><p class="eyebrow">{html.escape(label)}</p><ul>{"".join(lis)}</ul></div>'
            )
    articles = []
    leftover = []
    for href, title in sorted(index_links, key=lambda x: x[1].lower()):
        if href in used:
            continue
        item = f'<li><a href="{href}">{html.escape(title)}</a></li>'
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
    <div class="docs-index">{"".join(sections)}</div>
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
        ),
        encoding="utf-8",
    )
    print(f"mirrored {len(pages)} pages from secureblue.dev @{sha} -> {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
