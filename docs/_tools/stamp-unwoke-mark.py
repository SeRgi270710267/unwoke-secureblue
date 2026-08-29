#!/usr/bin/env python3
"""Insert the public Unwoke mark after the shebang if missing.

Does not obfuscate. MIT still allows copying *with* the notice.
"""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOKEN = "UNWOKE-SHIPPED-FIRST"
MARK = (
    "# Unwoke SecureBlue. Not affiliated with secureblue.\n"
    "# MIT License. Copyright (c) 2026 SeRgi270710267.\n"
    f"# {TOKEN}\n"
)

DIRS = [
    ROOT / "files" / "system" / "usr" / "libexec" / "unwoke",
    ROOT / "files" / "scripts",
]


def stamp_text(text: str) -> str | None:
    if TOKEN in text:
        return None
    lines = text.splitlines(keepends=True)
    if not lines:
        return MARK
    i = 0
    if lines[0].startswith("#!"):
        i = 1
        # skip one encoding cookie
        if i < len(lines) and "coding:" in lines[i]:
            i += 1
    insert = MARK if lines[0].endswith("\n") or i > 0 else MARK
    return "".join(lines[:i]) + insert + "".join(lines[i:])


def main() -> int:
    n = 0
    paths: list[Path] = []
    for d in DIRS:
        if not d.is_dir():
            continue
        for p in d.iterdir():
            if not p.is_file():
                continue
            if p.suffix in {".pyc"} or p.name == "__pycache__":
                continue
            paths.append(p)
    just = ROOT / "files" / "justfiles" / "unwoke.just"
    if just.is_file():
        paths.append(just)
    share = ROOT / "files" / "system" / "usr" / "share" / "unwoke"
    if share.is_dir():
        for p in share.rglob("*"):
            if not p.is_file():
                continue
            if p.suffix in {".conf", ".sh", ".rules", ".te", ".fc", ".cil"}:
                paths.append(p)
    for sub in (
        ROOT / "files" / "system" / "usr" / "lib" / "systemd",
        ROOT / "files" / "system" / "usr" / "etc" / "cryptsetup.conf",
    ):
        if sub.is_file():
            paths.append(sub)
        elif sub.is_dir():
            for p in sub.rglob("*"):
                if p.suffix in {".service", ".timer", ".preset"} and p.is_file():
                    paths.append(p)
    for p in paths:
        raw = p.read_text(encoding="utf-8", errors="replace")
        new = stamp_text(raw)
        if new is None:
            continue
        p.write_text(new, encoding="utf-8", newline="\n")
        print("stamped", p.relative_to(ROOT))
        n += 1
    print("stamped", n, "files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
