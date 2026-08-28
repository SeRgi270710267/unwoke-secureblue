#!/usr/bin/env python3
"""Fetch stock secureblue.dev markdown and wrap it in our chrome.

Writes only under docs/secureblue/. Never touches docs/faq, docs/features, etc.
"""
from __future__ import annotations

import datetime as dt
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
    "IMAGES.md",
    "CODE_OF_CONDUCT.md",
    "REPORTING.md",
    "404.md",
}

DONATE_NOTICE = """
<p class="alert caution"><strong>This money goes to secureblue. Not Unwoke SecureBlue.</strong> Open Collective, GitHub Sponsors, Monero, Coinbase — all theirs. We do not take donations and never will. <a href="donate/">Our donate page</a> exists to say that.</p>
"""

POSTINSTALL_NOTICE = """
<p class="alert note"><strong>Stock secureblue post-install.</strong> After you rebase onto Unwoke SecureBlue you still do most of this (their Secure Boot key, kargs, <code>ujust audit-secureblue</code>, USBGuard). Overlay extras are on our <a href="install/">Install</a> page. Canonical: <a href="https://secureblue.dev/post-install">secureblue.dev/post-install</a>.</p>
"""

CONTRIBUTING_NOTICE = """
<p class="alert caution"><strong>This is how you contribute to <em>secureblue</em>, not Unwoke SecureBlue.</strong> PRs against their repo, their AI ban, their Discord, their Covenant — all them. Overlay bugs and patches go to <a href="https://github.com/SeRgi270710267/unwoke-secureblue">our GitHub</a>. We do not use their CoC; see <a href="conduct/">Conduct</a>.</p>
"""

INCLUDE_RE = re.compile(
    r"\{%\s*include\s+alert\.html\s+type='([^']+)'\s+content='((?:\\'|[^'])*)'\s*%\}",
    re.I,
)
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
        kind = m.group(1).lower()
        body = m.group(2).replace("\\'", "'").replace("<br>", "\n")
        return f"\n\n<div class=\"alert {kind}\"><p>{body}</p></div>\n\n"

    return INCLUDE_RE.sub(repl, text)


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
        extra = {
            "/donate": DONATE_NOTICE,
            "/post-install": POSTINSTALL_NOTICE,
            "/contributing": CONTRIBUTING_NOTICE,
        }.get(permalink.rstrip("/"), "")
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

    items = "\n".join(
        f'<li><a href="{href}">{title}</a></li>' for href, title in sorted(index_links, key=lambda x: x[1].lower())
    )
    index_body = f"""
    <h1>Stock secureblue docs</h1>
    <p>These pages are pulled daily from <a href="https://secureblue.dev">secureblue.dev</a> and wrapped in our chrome. Unwoke SecureBlue’s own FAQ, Features, Images, and Install are the main nav — this tree cannot overwrite them.</p>
    <ul>{items}</ul>
    <p>Not mirrored on purpose: their homepage, image catalog, and code of conduct. Donate and contributing are mirrored with banners so you cannot confuse their wallets or their PR process with ours. Use <a href="https://secureblue.dev">secureblue.dev</a> for the rest.</p>
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
