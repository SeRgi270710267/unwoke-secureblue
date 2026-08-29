#!/usr/bin/env python3
"""Read a tar stream on stdin, extract matching path prefixes, list all names.

Usage: crane export IMAGE - | extract-prefixes.py DEST NAMES.txt PREFIX [PREFIX ...]
Never runs the image. Missing prefixes are skipped (GNU tar would exit 2).
"""
from __future__ import annotations

import os
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

    extract_kwargs = {}
    if hasattr(tarfile, "data_filter"):
        extract_kwargs["filter"] = "data"

    n_members = 0
    n_extracted = 0
    with open(names_path, "w", encoding="utf-8") as names, tarfile.open(
        fileobj=sys.stdin.buffer, mode="r|*"
    ) as tf:
        for member in tf:
            n_members += 1
            name = member.name.lstrip("./")
            names.write(name + "\n")
            if ".." in name.split("/"):
                continue
            if name in keep_exact or name.startswith(keep_slash):
                member.name = name
                try:
                    tf.extract(member, dest, **extract_kwargs)
                    n_extracted += 1
                except (tarfile.ExtractError, OSError) as err:
                    print(f"skip {name}: {err}", file=sys.stderr)

    print(f"extract-prefixes: members={n_members} extracted={n_extracted}", file=sys.stderr)
    if n_members == 0:
        print("extract-prefixes: empty tar stream", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
