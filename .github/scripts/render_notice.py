#!/usr/bin/env python3
"""Fill the public GitHub Pages notice with the gated-site URL.

The URL is a login wall, not the docs. Registry names are rejected.

    python3 .github/scripts/render_notice.py --selftest
    UNWOKE_SITE_URL=https://example.pages.dev python3 .github/scripts/render_notice.py SRC DEST
"""

from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path
from urllib.parse import urlsplit

MARKER = "<!--GATE-->"


class NoticeError(Exception):
    pass


def safe_url(value: str) -> str:
    raw = value.strip()
    if not raw:
        return ""
    parts = urlsplit(raw)
    if parts.scheme != "https" or not parts.hostname:
        raise NoticeError("site url must be https")
    if parts.username or parts.password:
        raise NoticeError("site url must not carry credentials")
    host = parts.hostname.lower()
    if host == "ghcr.io" or host.endswith(".ghcr.io"):
        raise NoticeError("site url must not be the registry")
    if parts.query or parts.fragment:
        raise NoticeError("site url must not carry a query")
    return raw


def render(html: str, url: str) -> str:
    if MARKER not in html:
        raise NoticeError("notice template is missing the gate marker")
    link = safe_url(url)
    if not link:
        block = "<p>Access is by invitation from the owner.</p>"
    else:
        block = f'<p><a href="{link}">Sign in</a> to read the site.</p>'
    return html.replace(MARKER, block, 1)


def selftest() -> int:
    ok = True
    html = f"<main>{MARKER}</main>"
    out = render(html, "")
    if "href" in out or "ghcr.io" in out:
        print("selftest FAIL empty")
        ok = False
    out = render(html, "https://unwoke.pages.dev")
    if 'href="https://unwoke.pages.dev"' not in out:
        print("selftest FAIL link")
        ok = False
    for bad in (
        "http://unwoke.pages.dev",
        "https://user:pw@unwoke.pages.dev",
        "https://ghcr.io/owner/name",
        "https://unwoke.pages.dev/?x=1",
    ):
        try:
            render(html, bad)
            print(f"selftest FAIL accepted {bad}")
            ok = False
        except NoticeError:
            pass
    print("notice selftest " + ("ok" if ok else "FAILED"))
    return 0 if ok else 1


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        return selftest()
    if len(argv) != 3:
        print("usage: render_notice.py SRC DEST", file=sys.stderr)
        return 2
    src = Path(argv[1])
    dest = Path(argv[2])
    try:
        text = render(src.joinpath("index.html").read_text(encoding="utf-8"), os.environ.get("UNWOKE_SITE_URL", ""))
    except (OSError, NoticeError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    (dest / "index.html").write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
