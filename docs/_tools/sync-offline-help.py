#!/usr/bin/env python3
"""Copy Tutorials into the overlay so Setup works offline."""
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "docs" / "tutorials"
DST = ROOT / "files" / "system" / "usr" / "share" / "unwoke" / "help"
CSS = ROOT / "docs" / "css" / "main.css"
LOGO = ROOT / "docs" / "assets" / "logo.svg"
SITE = "https://sergi270710267.github.io/unwoke-secureblue"


def rewrite(html: str, depth: int) -> str:
    prefix = "../" * depth if depth else ""
    html = re.sub(r'<base href="[^"]*">\s*', "", html)
    html = re.sub(r'href="css/main\.css[^"]*"', f'href="{prefix}css/main.css"', html)
    html = re.sub(r'href="assets/logo\.svg[^"]*"', f'href="{prefix}assets/logo.svg"', html)
    html = re.sub(r'src="assets/logo\.svg[^"]*"', f'src="{prefix}assets/logo.svg"', html)
    html = re.sub(
        r'href="tutorials/([a-z0-9-]+)/"',
        lambda m: f'href="{prefix}{m.group(1)}/index.html"',
        html,
    )
    html = html.replace('href="tutorials/"', f'href="{prefix}index.html"')
    for page in (
        "install",
        "post-install",
        "features",
        "compared",
        "faq",
        "images",
        "brand",
        "changelog",
        "factory",
        "stock-issues",
        "secureblue",
    ):
        html = html.replace(f'href="{page}/"', f'href="{SITE}/{page}/"')
        html = html.replace(f'href="{page}/#', f'href="{SITE}/{page}/#')
    html = html.replace('href="./"', f'href="{SITE}/"')
    # Compact local nav
    local_nav = (
        '    <nav id="site-menu" aria-label="Primary">\n'
        "      <ul>\n"
        f'        <li><a href="{prefix}index.html">Unwoke help (offline)</a></li>\n'
        f'        <li><a href="{SITE}/tutorials/">Online tutorials</a></li>\n'
        "      </ul>\n"
        "    </nav>\n"
    )
    html = re.sub(
        r'<nav id="site-menu"[^>]*>.*?</nav>',
        local_nav,
        html,
        count=1,
        flags=re.S,
    )
    return html


def main() -> None:
    if DST.exists():
        shutil.rmtree(DST)
    (DST / "css").mkdir(parents=True)
    (DST / "assets").mkdir(parents=True)
    shutil.copy2(CSS, DST / "css" / "main.css")
    if LOGO.exists():
        shutil.copy2(LOGO, DST / "assets" / "logo.svg")
    for src in SRC.rglob("index.html"):
        rel = src.relative_to(SRC)
        dest = DST / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        depth = 0 if rel.parent == Path(".") else 1
        dest.write_text(rewrite(src.read_text(encoding="utf-8"), depth), encoding="utf-8", newline="\n")
        print(dest.relative_to(ROOT))


if __name__ == "__main__":
    main()
