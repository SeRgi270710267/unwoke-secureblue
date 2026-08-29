#!/usr/bin/env python3
"""Rebuild the tutorials hub and vendor blocks from vendor-installers.json."""
from __future__ import annotations

import html
import json
import re
from collections import OrderedDict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / "docs" / "tutorials"
CORE = Path(__file__).with_name("tutorials-core.json")
VENDORS = ROOT / "files" / "system" / "usr" / "share" / "unwoke" / "vendor-installers.json"
HUB = DOCS / "index.html"
START = "<!-- vendor-generated:start -->"
END = "<!-- vendor-generated:end -->"

KIND_BLURB = {
    "https-ok": "Open in Trivalent. No extra package.",
    "wireguard-import": "WireGuard import. No extra daemon.",
    "proton-version-json": "Official RPM after live SHA512. Asked userns.",
    "yum-repo": "Official repo after you accept gpgcheck=1.",
}

NAV = """        <li><a href="./"><img src="assets/logo.svg?v=4" alt="">Unwoke SecureBlue</a></li>
        <li><a href="features/">Features</a></li>
        <li><a href="compared/">Compared</a></li>
        <li><a href="factory/">Factory</a></li>
        <li><a href="brand/">Brand</a></li>
        <li><a href="changelog/">Changelog</a></li>
        <li><a href="images/">Images</a></li>
        <li><a href="install/">Install</a></li>
        <li><a href="post-install/">Post-install</a></li>
        <li aria-current="page"><a href="tutorials/">Tutorials</a></li>
        <li><a href="faq/">FAQ</a></li>
        <li><a href="contributing/">Contributing</a></li>
        <li><a href="conduct/">Conduct</a></li>
        <li><a href="donate/">Donate</a></li>
        <li><a href="secureblue/">Their docs</a></li>
        <li><a href="https://github.com/SeRgi270710267/unwoke-secureblue">GitHub</a></li>"""


def esc(s: str) -> str:
    return html.escape(s, quote=True)


def load_vendors() -> dict:
    return json.loads(VENDORS.read_text(encoding="utf-8")).get("vendors") or {}


def groups(vendors: dict) -> OrderedDict[str, list[tuple[str, dict]]]:
    out: OrderedDict[str, list[tuple[str, dict]]] = OrderedDict()
    for name, spec in vendors.items():
        slug = spec.get("tutorial") or spec.get("group") or name
        out.setdefault(slug, []).append((name, spec))
    return out


def card(href: str, eyebrow: str, h3: str, p: str) -> str:
    return (
        f'      <a class="card" href="{esc(href)}">\n'
        f'        <p class="eyebrow">{esc(eyebrow)}</p>\n'
        f"        <h3>{esc(h3)}</h3>\n"
        f"        <p>{esc(p)}</p>\n"
        f"      </a>\n"
    )


def vendor_block(slug: str, items: list[tuple[str, dict]]) -> str:
    lines = [
        START,
        '<div class="alert tip">',
        "<p><strong>From the vendor list</strong> (watched and healed twice a day).",
        f"<code>ujust install-vendor NAME</code> or Setup → Strict apps. Group: <code>{esc(slug)}</code>.</p>",
        "<ul>",
    ]
    for name, spec in items:
        kind = spec.get("kind") or ""
        title = spec.get("title") or name
        rec = "recommended" if spec.get("strictest") else "asked"
        blurb = KIND_BLURB.get(kind, kind)
        cmd = f"ujust install-vendor {name}"
        lines.append(
            f"<li><strong>{esc(title)}</strong> (<code>{esc(name)}</code>, {esc(rec)}) — "
            f"{esc(blurb)} <code>{esc(cmd)}</code></li>"
        )
    lines += [
        "</ul>",
        "<p>Probe: <code>ujust check-vendor-installers</code>. New app = stanza in "
        "<code>vendor-installers.json</code>, not a one-off tutorial fork.</p>",
        "</div>",
        END,
    ]
    return "\n".join(lines) + "\n"


def inject(path: Path, block: str) -> None:
    text = path.read_text(encoding="utf-8")
    if START in text and END in text:
        text = re.sub(
            re.escape(START) + r".*?" + re.escape(END),
            block.strip(),
            text,
            count=1,
            flags=re.S,
        )
    else:
        if "</ol>" in text:
            text = text.replace("</ol>", "</ol>\n" + block, 1)
        else:
            text = text.replace("</main>", block + "  </main>", 1)
    path.write_text(text, encoding="utf-8", newline="\n")


def write_missing_page(slug: str, items: list[tuple[str, dict]]) -> None:
    dest = DOCS / slug / "index.html"
    if dest.is_file():
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    titles = [spec.get("title") or n for n, spec in items]
    h1 = titles[0] if len(titles) == 1 else slug.replace("-", " ").title()
    rec = [n for n, s in items if s.get("strictest")]
    dest.write_text(
        f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="theme-color" content="#050a16">
  <meta name="color-scheme" content="dark">
  <title>{esc(h1)} | Tutorials | Unwoke SecureBlue</title>
  <meta name="description" content="Strict installer for {esc(slug)}. Generated from vendor-installers.json.">
  <base href="/unwoke-secureblue/">
  <link rel="icon" href="assets/logo.svg?v=4" type="image/svg+xml">
  <link rel="stylesheet" href="css/main.css?v=13">
</head>
<body>
  <a class="skip" href="#content">Skip to content</a>
  <header>
    <nav id="site-menu" aria-label="Primary">
      <ul>
{NAV}
      </ul>
    </nav>
  </header>
  <main id="content">
    <p class="eyebrow">Strict apps</p>
    <h1>{esc(h1)}</h1>
    <p><span class="chip">Keep locked</span> Generated from <code>vendor-installers.json</code>. Watched and healed with every other vendor. No store.</p>
    {vendor_block(slug, items)}
    <p>Recommended keys first: {esc(", ".join(rec) or "none marked")}. Use Setup → Strict apps or <code>ujust install-vendor NAME</code>.</p>
    <nav class="tutorial-nav" aria-label="Adjacent tutorials">
      <a href="tutorials/">All tutorials</a>
    </nav>
  </main>
  <footer>
    <p>Not affiliated with secureblue.</p>
  </footer>
</body>
</html>
""",
        encoding="utf-8",
        newline="\n",
    )
    print(f"created {dest.relative_to(ROOT)}")


def write_hub(core: dict, grouped: OrderedDict) -> None:
    parts = [
        "<!DOCTYPE html>",
        '<html lang="en">',
        "<head>",
        '  <meta charset="utf-8">',
        '  <meta name="viewport" content="width=device-width, initial-scale=1">',
        '  <meta name="theme-color" content="#050a16">',
        '  <meta name="color-scheme" content="dark">',
        "  <title>Tutorials | Unwoke SecureBlue</title>",
        '  <meta name="description" content="Everyday Unwoke tasks the secure way. Vendor apps are generated from vendor-installers.json.">',
        '  <base href="/unwoke-secureblue/">',
        '  <link rel="icon" href="assets/logo.svg?v=4" type="image/svg+xml">',
        '  <link rel="stylesheet" href="css/main.css?v=13">',
        "</head>",
        "<body>",
        '  <a class="skip" href="#content">Skip to content</a>',
        "  <header>",
        '    <nav id="site-menu" aria-label="Primary">',
        "      <ul>",
        NAV,
        "      </ul>",
        "    </nav>",
        "  </header>",
        '  <main id="content">',
        "    <h1>Tutorials</h1>",
        "    <p>Common things on this desktop, <strong>secure path first</strong>.",
        "    Vendor apps below are generated from <code>vendor-installers.json</code> at Pages deploy so the hub cannot drift.</p>",
        '    <div class="alert tip">',
        "      <p><strong>How to use these.</strong> The recommended step keeps the lock.",
        "      Nothing auto-unlocks Flathub, Bluetooth, the webcam, JIT, or a store (there is no store).</p>",
        "    </div>",
        '    <p>Install: <a href="install/">Install</a>. Checklist: <a href="post-install/">Post-install</a>.',
        '    Vs stock: <a href="compared/">Compared</a>.</p>',
        "",
    ]
    for sec in core.get("sections") or []:
        parts.append(f'    <p class="section-label">{esc(sec["label"])}</p>')
        parts.append('    <div class="cards">')
        for c in sec.get("cards") or []:
            parts.append(card(c["href"], c["eyebrow"], c["h3"], c["p"]).rstrip())
        parts.append("    </div>")
        parts.append("")
    parts.append('    <p class="section-label">Strict apps (from the vendor list)</p>')
    parts.append('    <div class="cards">')
    for slug, items in grouped.items():
        titles = [s.get("title") or n for n, s in items]
        h3 = titles[0] if len(set(t.split()[0] for t in titles)) == 1 else slug.replace("-", " ").title()
        if slug == "proton":
            h3, eyebrow, blurb = "Mail, Pass, VPN", "Proton.me", "Wizard, not a store. Trivalent/WireGuard first. SHA512 on official RPMs."
        elif slug == "ivpn":
            h3, eyebrow, blurb = "WireGuard, then official app", "IVPN", "VPN + AntiTracker in their client. Import first. No Snap."
        elif slug == "mullvad":
            h3, eyebrow, blurb = "VPN, WireGuard first", "Mullvad", "Same vendor list. Official app only if you accept their repo."
        else:
            eyebrow = slug.replace("-", " ").title()
            blurb = "Watched and healed. Strictest keys first. No store."
            h3 = h3.split("(")[0].strip()
        parts.append(card(f"tutorials/{slug}/", eyebrow, h3, blurb).rstrip())
    parts.append("    </div>")
    parts += [
        "  </main>",
        "  <footer>",
        '    <a class="brand" href="./"><img src="assets/logo.svg?v=4" width="128" height="128" alt=""><span class="accent">Unwoke</span> <span class="sb">SecureBlue</span></a>',
        '    <ul id="social">',
        '      <li><a href="install/">Install</a></li>',
        '      <li><a href="post-install/">Post-install</a></li>',
        '      <li><a href="faq/">FAQ</a></li>',
        "    </ul>",
        "    <p>Not affiliated with secureblue.</p>",
        "  </footer>",
        "</body>",
        "</html>",
        "",
    ]
    HUB.write_text("\n".join(parts), encoding="utf-8", newline="\n")
    print(f"wrote {HUB.relative_to(ROOT)}")


def main() -> int:
    if not VENDORS.is_file():
        print(f"missing {VENDORS}", file=__import__("sys").stderr)
        return 1
    core = json.loads(CORE.read_text(encoding="utf-8"))
    vendors = load_vendors()
    grouped = groups(vendors)
    write_hub(core, grouped)
    for slug, items in grouped.items():
        write_missing_page(slug, items)
        page = DOCS / slug / "index.html"
        inject(page, vendor_block(slug, items))
        print(f"updated {page.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
