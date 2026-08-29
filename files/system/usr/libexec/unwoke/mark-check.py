#!/usr/bin/env python3
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
"""Fail compose, inspect, or the PR gate if overlay files lack the public mark.

Does not obfuscate. MIT still allows a copy *with* the copyright notice.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

TOKEN = "UNWOKE-SHIPPED-FIRST"
SKIP_NAMES = {"LICENSE", "flavor"}
SKIP_SUFFIX = {".jpg", ".jpeg", ".png", ".svg", ".pyc", ".woff", ".woff2"}
# Tiny generated identifier files, or stock text we overlay-replace by path:
IMAGE_EXTRAS = (
    "usr/libexec/secureblue/harden_flatpak.py",
    "usr/libexec/secureblue-motd",
    "usr/etc/cryptsetup.conf",
    "usr/etc/gtk-3.0/gtk.css",
    "usr/etc/gtk-4.0/gtk.css",
    "usr/etc/xdg/kdeglobals",
    "usr/etc/xdg/kscreenlockerrc",
)


def skip(path: Path) -> bool:
    if path.name in SKIP_NAMES:
        return True
    if path.suffix.lower() in SKIP_SUFFIX:
        return True
    if "__pycache__" in path.parts or "upstream-snapshots" in path.parts:
        return True
    if "help" in path.parts and "assets" in path.parts:
        return True
    return False


def check_file(path: Path) -> bool:
    if skip(path) or not path.is_file():
        return True
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False
    return TOKEN in text


def iter_image(prefix: Path) -> list[Path]:
    found: list[Path] = []
    seen: set[Path] = set()

    def add(p: Path) -> None:
        rp = p.resolve() if p.exists() else p
        if rp in seen:
            return
        seen.add(rp)
        found.append(p)

    for rel in (
        "usr/libexec/unwoke",
        "usr/share/unwoke",
        "usr/lib/systemd",
        "usr/share/applications",
        "usr/etc/profile.d",
        "usr/etc/brave-origin",
        "usr/etc/trivalent",
        "usr/etc/chromium",
        "usr/etc/dconf",
        "usr/share/fish",
        "usr/share/glib-2.0/schemas",
        "usr/share/gnome-background-properties",
        "usr/share/wallpapers/UnwokeSecureBlue",
    ):
        root = prefix / rel
        if not root.exists():
            continue
        if root.is_file():
            add(root)
            continue
        for p in root.rglob("*"):
            if not p.is_file():
                continue
            rel_s = str(p.relative_to(prefix)).replace("\\", "/")
            if "unwoke" in rel_s.lower() or rel.startswith("usr/share/unwoke"):
                add(p)
    for rel in IMAGE_EXTRAS:
        p = prefix / rel
        if p.is_file():
            add(p)
    motd = prefix / "usr/libexec/secureblue-motd"
    if motd.is_file():
        add(motd)
    return found


def iter_tree(root: Path) -> list[Path]:
    found: list[Path] = []
    for rel in (
        "files/gschema-overrides",
        "files/justfiles",
        "files/scripts",
        "files/system",
        "recipes",
    ):
        d = root / rel
        if not d.exists():
            continue
        if d.is_file():
            found.append(d)
            continue
        for p in d.rglob("*"):
            if p.is_file():
                found.append(p)
    prep = root / ".github/workflows/isos/prep_rootfs.sh"
    if prep.is_file():
        found.append(prep)
    return found


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "prefix",
        nargs="?",
        default=".",
        help="Image root (/ at compose, extract dir at inspect) or git root with --tree",
    )
    ap.add_argument(
        "--tree",
        action="store_true",
        help="Check overlay sources in the git tree, not an installed image",
    )
    args = ap.parse_args()
    prefix = Path(args.prefix).resolve()
    paths = iter_tree(prefix) if args.tree else iter_image(prefix)
    missing: list[str] = []
    checked = 0
    for p in paths:
        if skip(p) or not p.is_file():
            continue
        checked += 1
        if not check_file(p):
            try:
                missing.append(str(p.relative_to(prefix)).replace("\\", "/"))
            except ValueError:
                missing.append(str(p))
    if missing:
        print("FAIL: unmarked overlay files:", file=sys.stderr)
        for name in sorted(missing):
            print(" ", name, file=sys.stderr)
        return 1
    if checked == 0:
        print("FAIL: mark-check found no overlay files", file=sys.stderr)
        return 1
    print("unwoke mark: ok", checked, "files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
