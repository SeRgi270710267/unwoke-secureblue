#!/usr/bin/env python3
"""Least-privilege checks for workflow files.

- The workflow token starts at permissions: {} and each job grants what it needs.
- No pull_request_target and no auto-merge.
- Every job has an explicit timeout-minutes (long bakes use the platform cap).
- Every workflow has a concurrency group so a new PR push can cancel only that PR.

    python3 .github/scripts/workflow_policy.py
    python3 .github/scripts/workflow_policy.py --selftest
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = ROOT / ".github" / "workflows"
JOB_KEY = re.compile(r"^  ([A-Za-z0-9_-]+):\s*(?:#.*)?$")
TOP_KEY = re.compile(r"^[A-Za-z0-9_-]+:\s*")


def job_blocks(text: str) -> list[tuple[str, str]]:
    lines = text.splitlines()
    start = None
    for index, line in enumerate(lines):
        if line == "jobs:":
            start = index + 1
            break
    if start is None:
        return []
    blocks: list[tuple[str, str]] = []
    current_name = None
    current: list[str] = []
    for line in lines[start:]:
        if line.strip() and not line.startswith(" ") and not line.startswith("#"):
            break
        match = JOB_KEY.match(line)
        if match:
            if current_name is not None:
                blocks.append((current_name, "\n".join(current)))
            current_name = match.group(1)
            current = [line]
            continue
        if current_name is not None:
            current.append(line)
    if current_name is not None:
        blocks.append((current_name, "\n".join(current)))
    return blocks


def check_text(name: str, text: str) -> list[str]:
    problems = []
    if not re.search(r"(?m)^permissions:\s*\{\}\s*$", text):
        problems.append(f"{name}: workflow permissions must be {{}}")
    for line in text.splitlines():
        # A real trigger or input. The ban itself is allowed to name the words.
        if re.match(r"^\s*(-\s*)?(pull_request_target|enable-auto-merge):", line):
            problems.append(f"{name}: pull_request_target or auto-merge is not allowed")
    if not re.search(r"(?m)^concurrency:\s*$", text):
        problems.append(f"{name}: concurrency group is missing")
    jobs = job_blocks(text)
    if not jobs:
        problems.append(f"{name}: no jobs")
    for job, body in jobs:
        if not re.search(r"(?m)^[ ]+timeout-minutes:\s*\d+\s*$", body):
            problems.append(f"{name}: job {job} is missing timeout-minutes")
    return problems


def workflow_texts() -> list[tuple[str, str]]:
    if not WORKFLOWS.is_dir():
        return []
    found = []
    for path in sorted(WORKFLOWS.glob("*.yml")) + sorted(WORKFLOWS.glob("*.yaml")):
        found.append((path.name, path.read_text(encoding="utf-8")))
    return found


def selftest() -> int:
    good = """name: example
on:
  pull_request:
permissions: {}
concurrency:
  group: example
  cancel-in-progress: true
jobs:
  gate:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - run: echo ok
"""
    bad = good.replace("permissions: {}", "permissions:\n  contents: write").replace(
        "    timeout-minutes: 15\n", ""
    )
    ok = True
    if check_text("good.yml", good):
        print("selftest: a tight workflow was refused")
        print(check_text("good.yml", good))
        ok = False
    if not check_text("bad.yml", bad):
        print("selftest: a loose workflow was accepted")
        ok = False
    if not check_text("target.yml", good.replace("pull_request:", "pull_request_target:")):
        print("selftest: pull_request_target was accepted")
        ok = False
    named = good + "      - name: No pull_request_target / auto-merge\n"
    if check_text("named.yml", named):
        print("selftest: naming the ban was refused")
        print(check_text("named.yml", named))
        ok = False
    print("workflow policy selftest " + ("ok" if ok else "FAILED"))
    return 0 if ok else 1


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        return selftest()
    files = workflow_texts()
    if not files:
        print("workflow policy: no workflows", file=sys.stderr)
        return 1
    problems = []
    for name, text in files:
        problems.extend(check_text(name, text))
    if problems:
        print("workflow policy: FAIL")
        for item in problems:
            print(item)
        return 1
    print(f"workflow policy: ok {len(files)} workflows")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
