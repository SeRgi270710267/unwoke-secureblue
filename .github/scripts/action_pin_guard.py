#!/usr/bin/env python3
"""Require third-party GitHub Actions to be pinned to a full commit SHA.

A moving tag (@v4) can change what the factory runs. Each pin keeps a
same-line version comment so a human can see what the SHA is:

    uses: actions/checkout@<40 hex> # v4.2.2

    python3 .github/scripts/action_pin_guard.py
    python3 .github/scripts/action_pin_guard.py --selftest
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = ROOT / ".github" / "workflows"
USES = re.compile(r"^\s*-?\s*uses:\s*(\S+)\s*(#.*)?$")
SHA = re.compile(r"^[0-9a-f]{40}$")
VERSION_COMMENT = re.compile(r"v?\d")


def check_text(name: str, text: str) -> list[str]:
    problems = []
    for number, line in enumerate(text.splitlines(), 1):
        match = USES.match(line)
        if not match:
            continue
        ref = match.group(1)
        comment = match.group(2) or ""
        if ref.startswith("./") or ref.startswith("docker://"):
            continue
        if "@" not in ref:
            problems.append(f"{name}:{number}: action is not pinned ({ref})")
            continue
        owner, sha = ref.rsplit("@", 1)
        if not owner or "/" not in owner:
            problems.append(f"{name}:{number}: action ref is not owner/name@sha")
            continue
        if not SHA.fullmatch(sha):
            problems.append(f"{name}:{number}: pin is not a 40-character SHA ({owner})")
            continue
        if not VERSION_COMMENT.search(comment):
            problems.append(f"{name}:{number}: pin is missing a version comment")
    return problems


def workflow_texts() -> list[tuple[str, str]]:
    found = []
    if not WORKFLOWS.is_dir():
        return found
    for path in sorted(WORKFLOWS.glob("*.yml")) + sorted(WORKFLOWS.glob("*.yaml")):
        found.append((path.name, path.read_text(encoding="utf-8")))
    return found


def selftest() -> int:
    good = "        uses: actions/checkout@" + ("a" * 40) + " # v4.2.2\n"
    bad_tag = "        uses: actions/checkout@v4\n"
    bad_comment = "        uses: actions/checkout@" + ("b" * 40) + "\n"
    local = "        uses: ./.github/actions/local\n"
    ok = True
    if check_text("good.yml", good):
        print("selftest: a pinned action was refused")
        ok = False
    if not check_text("tag.yml", bad_tag):
        print("selftest: a moving tag was accepted")
        ok = False
    if not check_text("nocomment.yml", bad_comment):
        print("selftest: a pin without a version comment was accepted")
        ok = False
    if check_text("local.yml", local):
        print("selftest: a local action was refused")
        ok = False
    print("action pin selftest " + ("ok" if ok else "FAILED"))
    return 0 if ok else 1


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        return selftest()
    problems = []
    files = workflow_texts()
    if not files:
        print("action pin: no workflows", file=sys.stderr)
        return 1
    for name, text in files:
        problems.extend(check_text(name, text))
    if problems:
        print("action pin: FAIL")
        for item in problems:
            print(item)
        return 1
    print(f"action pin: ok {len(files)} workflows")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
