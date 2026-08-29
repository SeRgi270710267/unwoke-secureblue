#!/usr/bin/env python3
"""Print `owner/repo <full-sha>` from the ISO baker pin. Never bumps it.

`git ls-remote URL SHA` matches refs, not commit objects. Our pin is tag v0.2
(840217d), so that check is a false alarm. Callers should ask GitHub for the
commit object instead.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ISO_YML = ROOT / ".github" / "workflows" / "iso.yml"
# Prefer the named checkout step so comments about ublue-os/titanoboa@main
# cannot steal the match.
BLOCK = re.compile(
    r"- name:\s*Checkout titanoboa\b.*?repository:\s*(\S+)\s*\n\s*ref:\s*([0-9a-f]{7,40})",
    re.S | re.I,
)
FALLBACK = re.compile(
    r"repository:\s*(\S*titanoboa\S*)\s*\n\s*ref:\s*([0-9a-f]{7,40})",
    re.I,
)


def parse(text: str | None = None) -> tuple[str, str]:
    raw = text if text is not None else ISO_YML.read_text(encoding="utf-8")
    m = BLOCK.search(raw) or FALLBACK.search(raw)
    if not m:
        raise SystemExit("could not parse titanoboa pin from iso.yml")
    repo, pin = m.group(1).strip(), m.group(2).strip()
    if "/" not in repo:
        raise SystemExit(f"titanoboa repository is not owner/repo: {repo}")
    return repo, pin


def main() -> None:
    repo, pin = parse()
    print(f"{repo} {pin}")


if __name__ == "__main__":
    try:
        main()
    except SystemExit as exc:
        print(str(exc) or "parse failed", file=sys.stderr)
        raise
