#!/usr/bin/env python3
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
"""Public mark: stamp, check, and keep it out of live browser policies.

Compose runs ``--apply`` so a new overlay file is marked without a human
reminder. Inspect and the PR gate check only (they must not rewrite git).

Live Chromium/Brave/Trivalent ``policies/managed/*.json`` must *not* contain
the token or ``UnwokeShippedFirst``. Those files are loaded by the browser.
An extra unrecognized policy would show in chrome://policy and is a uniqueness
we do not need. Real lock keys are unchanged. No phone-home. MIT stays MIT.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

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
SKIP_SUFFIX = {
    ".jpg",
    ".jpeg",
    ".png",
    ".svg",
    ".pyc",
    ".woff",
    ".woff2",
    ".sqlite",
}
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
    # RPM sqlite backup + sidecars. Stamping a db malforms Packages.
    if path.name.startswith(".rpmdb-pre-flavor"):
        return True
    if path.name.endswith(".sqlite-wal") or path.name.endswith(".sqlite-shm"):
        return True
    if "__pycache__" in path.parts or "upstream-snapshots" in path.parts:
        return True
    if "help" in path.parts and "assets" in path.parts:
        return True
    return False


def is_live_policy(path: Path) -> bool:
    """True for files the browser loads as managed enterprise policy."""
    if path.suffix.lower() != ".json":
        return False
    parts = [p.lower() for p in path.parts]
    try:
        i = parts.index("policies")
    except ValueError:
        return False
    return i + 1 < len(parts) and parts[i + 1] == "managed"


def scrub_policy(obj: object) -> object:
    if not isinstance(obj, dict):
        return obj
    return {k: v for k, v in obj.items() if k != JSON_KEY}


def write_json(path: Path, obj: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(obj, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
        newline="\n",
    )


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


def stamp_source_json(text: str) -> str | None:
    """Mark overlay JSON that the browser does *not* load (share/, vendors, wallpaper)."""
    obj = json.loads(text)
    if not isinstance(obj, dict):
        return None
    if obj.get(JSON_KEY) == JSON_VAL and TOKEN in text:
        return None
    obj = {JSON_KEY: JSON_VAL, **{k: v for k, v in obj.items() if k != JSON_KEY}}
    return json.dumps(obj, indent=2, ensure_ascii=False) + "\n"


def stamp_payload(path: Path, text: str) -> str | None:
    suf = path.suffix.lower()
    if suf == ".json":
        return stamp_source_json(text)
    if suf == ".css":
        return stamp_css(text)
    if suf in {".html", ".xml"}:
        return stamp_html(text)
    if suf in {".yml", ".yaml"}:
        return stamp_yaml(text)
    if suf == ".cil":
        return stamp_hash(text, CIL_MARK)
    return stamp_hash(text)


def apply_one(path: Path) -> bool:
    if skip(path) or not path.is_file():
        return False
    raw = path.read_text(encoding="utf-8", errors="replace")
    if is_live_policy(path):
        obj = json.loads(raw)
        new_obj = scrub_policy(obj)
        new = json.dumps(new_obj, indent=2, ensure_ascii=False) + "\n"
        if TOKEN in new or JSON_KEY in new:
            raise SystemExit(f"FAIL: cannot scrub live policy {path}")
        if new_obj == obj and TOKEN not in raw:
            return False
        write_json(path, new_obj)
        return True
    new = stamp_payload(path, raw)
    if new is None or new == raw:
        return False
    path.write_text(new, encoding="utf-8", newline="\n")
    return True


def check_one(path: Path) -> str | None:
    if skip(path) or not path.is_file():
        return None
    text = path.read_text(encoding="utf-8", errors="replace")
    if is_live_policy(path):
        if TOKEN in text or JSON_KEY in text:
            return "live browser policy must not contain the public mark"
        return None
    if TOKEN not in text:
        return "missing UNWOKE-SHIPPED-FIRST"
    return None


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


def rel_str(path: Path, prefix: Path) -> str:
    try:
        return str(path.relative_to(prefix)).replace("\\", "/")
    except ValueError:
        return str(path)


def install_policy(src: Path, dst: Path) -> None:
    if not src.is_file():
        raise SystemExit(f"FAIL: missing policy source {src}")
    obj = json.loads(src.read_text(encoding="utf-8"))
    obj = scrub_policy(obj)
    text = json.dumps(obj, indent=2, ensure_ascii=False) + "\n"
    if TOKEN in text or JSON_KEY in text:
        raise SystemExit(f"FAIL: policy source still marked after scrub {src}")
    write_json(dst, obj)
    print("policy", dst)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "prefix",
        nargs="?",
        default=".",
        help="Image root (/ at compose) or git root with --tree",
    )
    ap.add_argument("--tree", action="store_true")
    ap.add_argument(
        "--apply",
        action="store_true",
        help="Stamp unmarked overlay files and scrub live browser policies, then check",
    )
    ap.add_argument(
        "--install-policy",
        nargs=2,
        metavar=("SRC", "DST"),
        help="Copy a share JSON pack to managed/ with the public mark stripped",
    )
    args = ap.parse_args()
    if args.install_policy:
        install_policy(Path(args.install_policy[0]), Path(args.install_policy[1]))
        return 0
    prefix = Path(args.prefix).resolve()
    paths = iter_tree(prefix) if args.tree else iter_image(prefix)
    applied = 0
    if args.apply:
        for p in paths:
            if skip(p) or not p.is_file():
                continue
            if apply_one(p):
                print("stamped", rel_str(p, prefix))
                applied += 1
        if applied:
            print("stamped", applied, "files")
    missing: list[str] = []
    leaked: list[str] = []
    checked = 0
    for p in paths:
        if skip(p) or not p.is_file():
            continue
        checked += 1
        err = check_one(p)
        if not err:
            continue
        name = rel_str(p, prefix)
        if "live browser policy" in err:
            leaked.append(name)
        else:
            missing.append(name)
    if leaked:
        print("FAIL: public mark leaked into live browser policy:", file=sys.stderr)
        for name in sorted(leaked):
            print(" ", name, file=sys.stderr)
        return 1
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
