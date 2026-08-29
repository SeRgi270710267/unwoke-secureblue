#!/usr/bin/env python3
"""Read a tar stream on stdin, copy matching path prefixes, list all names.

Usage: crane export IMAGE - | extract-prefixes.py DEST NAMES.txt PREFIX [PREFIX ...]
Never runs the image. Missing prefixes are skipped.
Uses extractfile() (not extract()) because stream tars cannot seek backwards.
"""
from __future__ import annotations

import os
import shutil
import sys
import tarfile


def main() -> int:
    if len(sys.argv) < 4:
        print("usage: extract-prefixes.py DEST NAMES.txt PREFIX [PREFIX ...]", file=sys.stderr)
        return 2
    dest, names_path, *prefixes = sys.argv[1:]
    os.makedirs(dest, exist_ok=True)
    keep_exact = set(prefixes)
    keep_slash = tuple(p.rstrip("/") + "/" for p in prefixes)

    n_members = 0
    n_extracted = 0
    with open(names_path, "w", encoding="utf-8") as names, tarfile.open(
        fileobj=sys.stdin.buffer, mode="r|*"
    ) as tf:
        for member in tf:
            n_members += 1
            name = member.name.lstrip("./")
            if member.isdir():
                kind = "dir"
            elif member.issym():
                kind = "symlink"
            elif member.islnk():
                kind = "hardlink"
            elif member.isreg():
                kind = "file"
            else:
                kind = "other"
            names.write(f"{kind}\t{name}\n")
            if ".." in name.split("/") or name.startswith("/"):
                continue
            if name not in keep_exact and not name.startswith(keep_slash):
                continue
            out_path = os.path.join(dest, name)
            parent = os.path.dirname(out_path)
            if parent:
                os.makedirs(parent, exist_ok=True)
            if member.isdir():
                os.makedirs(out_path, exist_ok=True)
                n_extracted += 1
                continue
            if member.issym():
                try:
                    os.symlink(member.linkname, out_path)
                    n_extracted += 1
                except OSError:
                    pass
                continue
            if member.islnk():
                target = os.path.join(dest, member.linkname.lstrip("./"))
                if os.path.isfile(target):
                    try:
                        os.link(target, out_path)
                    except OSError:
                        shutil.copy2(target, out_path)
                    n_extracted += 1
                continue
            # Devices / fifos: extractfile() raises on a stream.
            if not member.isreg():
                continue
            src = tf.extractfile(member)
            if src is None:
                continue
            with src, open(out_path, "wb") as out:
                shutil.copyfileobj(src, out)
            n_extracted += 1

    print(f"extract-prefixes: members={n_members} extracted={n_extracted}", file=sys.stderr)
    if n_members == 0:
        print("extract-prefixes: empty tar stream", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
