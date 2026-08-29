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


# Stock snippets that do the wrong thing (or not enough) on Unwoke.
# Inserted under the matching stock <pre> or paragraph at mirror time.
UNWOKE_CMDS: tuple[dict[str, object], ...] = (
    {
        "id": "flathub",
        "needles": ("ujust set-flathub-unfiltered", "Software store"),
        "code": "ujust set-flathub verified\n# or: ujust set-flathub full",
        "note": "Flathub is <strong>off</strong> here. There is no Bazaar/GNOME Software/Discover. "
        "<code>verified</code> matches stock’s default remote. <code>full</code> is their unfiltered.",
        "more": ("tutorials/install-apps/", "Install an app"),
    },
    {
        "id": "vpn",
        "needles": ("ujust install-vpn",),
        "code": "ujust install-proton\nujust install-ivpn\nujust install-mullvad\nujust install-vendor NAME",
        "note": "WireGuard import first (no extra daemon). Official RPM/repo only after live SHA512 "
        "or <code>gpgcheck=1</code>, and only if you accept the extra origin. No Snap, no unverified Flathub.",
        "more": ("tutorials/", "Tutorials"),
    },
    {
        "id": "rebase-stock",
        "needles": ("ujust rebase-secureblue", "bootc switch ghcr.io/secureblue"),
        "code": "rpm-ostree rebase ostree-image-signed:docker://ghcr.io/sergi270710267/unwoke-silverblue-trivalent:latest",
        "note": "That stock command rebases you <strong>off Unwoke</strong> onto their GHCR. Stay on "
        "<code>ghcr.io/sergi270710267/…</code> after the signed reboot. Pick the flavor on "
        '<a href="install/">Install</a>.',
        "more": ("images/", "Our images"),
    },
    {
        "id": "bluetooth",
        "needles": ("ujust set-bluetooth-modules",),
        "code": "ujust set-bluetooth on",
        "note": "Stock only loads BT kernel modules. We also mask <code>bluetooth.service</code> and "
        "<code>rfkill</code>. The stock command alone is not enough here. Wi-Fi is not touched.",
        "more": ("tutorials/bluetooth/", "Bluetooth tutorial"),
    },
    {
        "id": "webcam",
        "needles": ("ujust set-webcam-modules",),
        "code": "ujust set-camera-mic on",
        "note": "Webcam/mic capture is <strong>already locked</strong> (speakers stay). Stock’s command "
        "turns modules off; you want the opposite to use a camera. Then grant the browser: "
        "<code>ujust set-brave-devices off</code> if policy is blocking it.",
        "more": ("tutorials/camera-mic/", "Camera / mic"),
    },
    {
        "id": "avahi",
        "needles": ("unmask avahi-daemon", "systemctl unmask avahi"),
        "code": "ujust set-extra-daemons on",
        "note": "Avahi and ModemManager are masked on Unwoke. That one toggle is the overlay path. "
        "cups/geoclue stay stock’s masks. Then still open firewall mDNS as they describe.",
        "more": ("faq/#daemons", "Our FAQ"),
    },
    {
        "id": "brew",
        "needles": ("brew install", "Why does secureblue include Homebrew"),
        "code": "ujust set-brew on\n# new shell, then brew works like stock",
        "note": "Homebrew is off until you toggle it. Stock ships it on PATH.",
        "more": ("faq/#brew", "Our FAQ"),
    },
    {
        "id": "toolbox",
        "needles": ("ujust distrobox-assemble", "distrobox-assemble"),
        "code": "ujust set-toolbox on",
        "note": "<code>toolbox</code> / <code>distrobox</code> are wrappers until you opt in. "
        "<code>podman</code> stays. Then their Distrobox command works.",
        "more": ("tutorials/toolbox/", "toolbox tutorial"),
    },
    {
        "id": "audit",
        "needles": ("ujust audit-secureblue",),
        "code": "ujust audit-unwoke\nujust unwoke-status",
        "note": "Stock audit still applies (their kernel, USBGuard, kargs). Also run the overlay check "
        "so trampoline / flavor / no leftover store are covered.",
        "more": ("tutorials/check-health/", "Check health"),
    },
    {
        "id": "admin",
        "needles": ("ujust create-admin",),
        "code": "ujust set-admin-split add NAME\n# or skip the first-boot prompt: ujust set-admin-split off",
        "note": "Unwoke already asks for a daily (non-wheel) user before GDM/SDDM. Stock "
        "<code>create-admin</code> still exists if you skipped that. Wheel is blocked from the greeter.",
        "more": ("tutorials/daily-user/", "Daily user"),
    },
    {
        "id": "trivalent-flags",
        "needles": ("chrome://flags", "Trivalent post-install"),
        "code": "ujust set-trivalent-network-sandbox on   # default on *-trivalent\nujust set-trivalent-referrers on",
        "note": "On <code>*-trivalent</code>, JIT-less / no WebGL / extension block / NSS may already be "
        "forced by overlay policy. Origin uses <code>ujust set-brave-*</code>. Do not Bubblejail Trivalent.",
        "more": ("features/#trivalent", "Trivalent flavor"),
    },
)

PRE_BLOCK = re.compile(r"<pre\b[^>]*>.*?</pre>", re.I | re.S)
P_BLOCK = re.compile(r"<p\b[^>]*>.*?</p>", re.I | re.S)


def _unwoke_box(spec: dict[str, object]) -> str:
    sid = html.escape(str(spec["id"]), quote=True)
    code = html.escape(str(spec["code"]))
    note = str(spec["note"])
    more = spec.get("more")
    extra = ""
    if isinstance(more, tuple) and len(more) == 2:
        extra = (
            f' <a href="{html.escape(more[0], quote=True)}">{html.escape(more[1])}</a>.'
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


def annotate_unwoke_commands(fragment: str) -> str:
    """Under stock commands that differ here, add the Unwoke ujust. Idempotent."""
    for spec in UNWOKE_CMDS:
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
    """Keep {: #id} / {: .class} for Python-Markdown attr_list. Drop other kramdown."""

    def repl(m: re.Match[str]) -> str:
        inner = m.group(1).strip()
        if re.fullmatch(r"[#.][\w-]+(?:\s+[#.][\w-]+)*", inner):
            return m.group(0)
        return ""

    return KRAMDOWN_ATTR.sub(repl, text)


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
        body_html = annotate_unwoke_commands(body_html)
        extra = PAGE_NOTICES.get(permalink.rstrip("/"), "")
        if extra:
            body_html = extra + body_html
        canonical = "https://secureblue.dev" + permalink
        dest = out_dir_for(permalink)
        dest.mkdir(parents=True, exist_ok=True)
        page_title = f"{title} (mirrored)"
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
            "secureblue/",
        ),
        encoding="utf-8",
    )
    print(f"mirrored {len(pages)} pages from secureblue.dev @{sha} -> {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
