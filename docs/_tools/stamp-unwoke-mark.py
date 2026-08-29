#!/usr/bin/env python3
"""Stamp the git overlay tree, then check. Same code as compose ``mark-check --apply``.

Does not obfuscate. Does not write the public mark into live browser policies.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CHK = ROOT / "files" / "system" / "usr" / "libexec" / "unwoke" / "mark-check.py"


def main() -> int:
    return subprocess.call(
        [sys.executable, str(CHK), "--tree", "--apply", str(ROOT)]
    )


if __name__ == "__main__":
    raise SystemExit(main())
