#!/usr/bin/env python3
"""Insert the public Unwoke mark on overlay sources that still lack it.

Does not obfuscate. MIT still allows copying *with* the notice.
JSON gets a Chromium-ignored UnwokeShippedFirst string so a policy copy is grep-able.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOKEN = "UNWOKE-SHIPPED-FIRST"
JSON_KEY = "UnwokeShippedFirst"
JSON_VAL = (
    "UNWOKE-SHIPPED-FIRST. MIT License. Copyright (c) 2026 SeRgi270710267. "
    "Not affiliated with secureblue."
)
HASH_MARK = (
    "# Unwoke SecureBlue. Not affiliated with secureblue.\n"
    "# MIT License. Copyright (c) 2026 SeRgi270710267.\n"
    f"# {TOKEN}\n"
)
CSS_MARK = (
    "/* Unwoke SecureBlue. Not affiliated with secureblue. "
    "MIT License. Copyright (c) 2026 SeRgi270710267. "
    f"{TOKEN}. */\n"
)
HTML_MARK = (
    "<!-- Unwoke SecureBlue. Not affiliated with secureblue. "
    "MIT License. Copyright (c) 2026 SeRgi270710267. "
    f"{TOKEN}. -->\n"
)
CIL_MARK = (
    ";; Unwoke SecureBlue. Not affiliated with secureblue.\n"
    ";; MIT License. Copyright (c) 2026 SeRgi270710267.\n"
    f";; {TOKEN}\n"
)
SKIP_NAMES = {"LICENSE", "flavor"}
SKIP_SUFFIX = {".jpg", ".jpeg", ".png", ".svg", ".pyc"}


def stamp_hash(text: str, mark: str = HASH_MARK) -> str | None:
    if TOKEN in text:
        return None
    lines = text.splitlines(keepends=True)
    if not lines:
        return mark
    i = 0
    if lines[0].startswith("#!"):
        i = 1
        if i < len(lines) and "coding:" in lines[i]:
            i += 1
    return "".join(lines[:i]) + mark + "".join(lines[i:])


def stamp_yaml(text: str) -> str | None:
    if TOKEN in text:
        return None
    lines = text.splitlines(keepends=True)
    i = 0
    if lines and lines[0].strip() == "---":
        i = 1
    if i < len(lines) and "yaml-language-server" in lines[i]:
        i += 1
    return "".join(lines[:i]) + HASH_MARK + "".join(lines[i:])


def stamp_css(text: str) -> str | None:
    if TOKEN in text:
        return None
    return CSS_MARK + text


def stamp_html(text: str) -> str | None:
    if TOKEN in text:
        return None
    lines = text.splitlines(keepends=True)
    i = 0
    if lines and lines[0].lstrip().lower().startswith("<!doctype"):
        i = 1
    elif lines and lines[0].lstrip().startswith("<?xml"):
        i = 1
    return "".join(lines[:i]) + HTML_MARK + "".join(lines[i:])


def stamp_json(text: str) -> str | None:
    if TOKEN in text:
        return None
    obj = json.loads(text)
    if not isinstance(obj, dict):
        return None
    if JSON_KEY not in obj:
        obj = {JSON_KEY: JSON_VAL, **obj}
    elif TOKEN not in str(obj.get(JSON_KEY)):
        obj[JSON_KEY] = JSON_VAL
    else:
        return None
    return json.dumps(obj, indent=2, ensure_ascii=False) + "\n"


def stamp_text(path: Path, text: str) -> str | None:
    suf = path.suffix.lower()
    name = path.name
    if suf == ".json":
        return stamp_json(text)
    if suf in {".css"}:
        return stamp_css(text)
    if suf in {".html", ".xml"}:
        return stamp_html(text)
    if suf in {".yml", ".yaml"}:
        return stamp_yaml(text)
    if suf == ".cil":
        return stamp_hash(text, CIL_MARK)
    if suf in {
        ".sh",
        ".py",
        ".just",
        ".conf",
        ".rules",
        ".te",
        ".fc",
        ".service",
        ".timer",
        ".preset",
        ".desktop",
        ".override",
        ".fish",
        ".ks",
        ".txt",
        ".list",
        ".rpm",
        ".flatpak",
        ".mount",
    }:
        return stamp_hash(text)
    if suf == "":
        return stamp_hash(text)
    if name in {"00-unwoke", "dconf-gnome-privacy", "dconf-thumbnails-off", "dolphin-thumbnails-off"}:
        return stamp_hash(text)
    return stamp_hash(text)


def should_stamp(path: Path) -> bool:
    if not path.is_file():
        return False
    if path.name in SKIP_NAMES or path.suffix.lower() in SKIP_SUFFIX:
        return False
    if "__pycache__" in path.parts or "upstream-snapshots" in path.parts:
        return False
    if "help" in path.parts and "assets" in path.parts:
        return False
    return True


def collect() -> list[Path]:
    paths: list[Path] = []
    for rel in (
        "files/gschema-overrides",
        "files/justfiles",
        "files/scripts",
        "files/system",
        "recipes",
    ):
        d = ROOT / rel
        if not d.exists():
            continue
        if d.is_file():
            paths.append(d)
            continue
        for p in d.rglob("*"):
            if should_stamp(p):
                paths.append(p)
    prep = ROOT / ".github/workflows/isos/prep_rootfs.sh"
    if prep.is_file():
        paths.append(prep)
    return paths


def main() -> int:
    n = 0
    for p in collect():
        raw = p.read_text(encoding="utf-8", errors="replace")
        new = stamp_text(p, raw)
        if new is None or new == raw:
            continue
        p.write_text(new, encoding="utf-8", newline="\n")
        print("stamped", p.relative_to(ROOT))
        n += 1
    print("stamped", n, "files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
