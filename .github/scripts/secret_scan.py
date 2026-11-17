#!/usr/bin/env python3
"""Secret scan for this public overlay tree.

Reports a path, a line number, and a rule name. Matched values are never
printed. The same check runs in pr-gate and, if you install it, before
each commit.

    python3 .github/scripts/secret_scan.py
    python3 .github/scripts/secret_scan.py --staged
    python3 .github/scripts/secret_scan.py --selftest

A proven false positive may end the line with "secret-scan: allow" and a
short reason. Public keys (cosign.pub, keys/*.pub) are not secrets.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ALLOW_MARK = "secret-scan: allow"
MAX_BYTES = 2_000_000
SKIP_SUFFIXES = {
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".woff", ".woff2",
    ".ttf", ".otf", ".svg", ".mp4", ".zip", ".gz", ".iso",
}
SKIP_FILES = {"secret_scan.py"}

FORBIDDEN_NAMES = [
    (re.compile(r"(^|/)\.env(\.[^/]*)?$"), "env-file"),
    (re.compile(r"(^|/)cosign\.(key|private)$", re.I), "signing-key"),
    (re.compile(r"\.(pem|p12|pfx|jks|keystore)$", re.I), "key-file"),
    (re.compile(r"(^|/)(id_rsa|id_ed25519|id_ecdsa)$"), "ssh-key"),
    (re.compile(r"\.(har|sqlite3?)$", re.I), "capture-or-database"),
]
FORBIDDEN_EXEMPT = {".env.example"}

SECRET_RULES = [
    ("private-key", r"-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY(?: BLOCK)?-----"),
    ("github-token", r"\bgh[pousr]_[A-Za-z0-9]{36,}\b"),
    ("github-pat", r"\bgithub_pat_[A-Za-z0-9_]{60,}\b"),
    ("aws-access-key", r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"),
    ("slack-token", r"\bxox[abposr]-[A-Za-z0-9-]{10,}\b"),
    ("url-credentials", r"\b[a-z][a-z0-9+.-]*://[^\s:/@\"']{1,64}:[^\s:/@\"']{6,}@[A-Za-z0-9.-]+"),
    (
        "assigned-secret",
        r"\b(?:SIGNING_SECRET|COSIGN_PASSWORD|COSIGN_KEY|GH_TOKEN|GITHUB_TOKEN|XAI_API_KEY|GROQ_API_KEY|UNWOKE_AI_KEY)\s*[=:]\s*[\"'][A-Za-z0-9_\-+/=.]{20,}[\"']",
    ),
]

COMPILED = [(name, re.compile(rx)) for name, rx in SECRET_RULES]


def git_files(staged: bool) -> list[str]:
    if staged:
        out = subprocess.run(
            ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z"],
            cwd=ROOT,
            capture_output=True,
            check=True,
        ).stdout
    else:
        out = subprocess.run(
            ["git", "ls-files", "-z"],
            cwd=ROOT,
            capture_output=True,
            check=True,
        ).stdout
    return [p for p in out.decode("utf-8", "replace").split("\0") if p]


def staged_text(path: str) -> str | None:
    res = subprocess.run(["git", "show", ":" + path], cwd=ROOT, capture_output=True)
    if res.returncode != 0 or len(res.stdout) > MAX_BYTES or b"\0" in res.stdout[:8000]:
        return None
    return res.stdout.decode("utf-8", "replace")


def file_text(path: str) -> str | None:
    full = ROOT / path
    try:
        if not full.is_file() or full.stat().st_size > MAX_BYTES:
            return None
        data = full.read_bytes()
    except OSError:
        return None
    if b"\0" in data[:8000]:
        return None
    return data.decode("utf-8", "replace")


def name_findings(path: str) -> list[tuple[str, int, str]]:
    base = path.rsplit("/", 1)[-1]
    if base in FORBIDDEN_EXEMPT or base.endswith(".pub"):
        return []
    return [(path, 0, rule) for rx, rule in FORBIDDEN_NAMES if rx.search(path)]


def text_findings(path: str, text: str) -> list[tuple[str, int, str]]:
    found = []
    for number, line in enumerate(text.splitlines(), 1):
        if ALLOW_MARK in line:
            continue
        for name, rx in COMPILED:
            if rx.search(line):
                found.append((path, number, name))
                break
    return found


def scan(paths: list[str], staged: bool) -> list[tuple[str, int, str]]:
    findings = []
    for path in paths:
        findings.extend(name_findings(path))
        base = path.rsplit("/", 1)[-1]
        if base in SKIP_FILES or Path(path).suffix.lower() in SKIP_SUFFIXES:
            continue
        text = staged_text(path) if staged else file_text(path)
        if text is None:
            continue
        findings.extend(text_findings(path, text))
    return findings


def report(findings: list[tuple[str, int, str]]) -> int:
    if not findings:
        print("secret scan: clean")
        return 0
    for path, line, rule in findings:
        where = f"{path}:{line}" if line else path
        print(f"secret scan: {where}: {rule}")
    print(
        f"secret scan: {len(findings)} finding(s). Values are not printed. "
        f"Move the value to a GitHub secret, or end a proven false positive with "
        f"'{ALLOW_MARK} <reason>'."
    )
    return 1


def selftest() -> int:
    # Samples are built at run time so this file never contains a match.
    j = "".join
    bad = {
        "private-key": j(["-----BEGIN ", "OPENSSH PRIVATE", " KEY-----"]),
        "github-token": j(["gh", "p_", "A1b2" * 9]),
        "github-pat": j(["github_pat_", "Ab" * 40]),
        "aws-access-key": j(["AKIA", "A1B2C3D4E5F6G7H8"]),
        "slack-token": j(["xoxb-", "a1" * 12]),
        "url-credentials": j(["https://", "user", ":", "hunter22", "@example.org"]),
        "assigned-secret": j(["SIGNING_SECRET", '="', "q" * 24, '"']),
    }
    ok = True
    for rule, sample in bad.items():
        got = [item[2] for item in text_findings("t.txt", sample)]
        if rule not in got:
            print(f"selftest: {rule} was not detected")
            ok = False
    good = [
        "cosign_private_key: ${{ secrets.SIGNING_SECRET }}",
        "GH_TOKEN: ${{ github.token }}",
        "XAI_API_KEY: ${{ secrets.XAI_API_KEY }}",
        j(["ghp_", "short"]),
        j(["-----BEGIN ", "PUBLIC KEY-----"]),
        j(["SIGNING_SECRET", '="', "q" * 24, '"  # ', ALLOW_MARK, " sample"]),
        "pubkey file stays: keys/secureblue.pub",
    ]
    for line in good:
        if text_findings("t.txt", line):
            print("selftest: false positive on a safe line")
            ok = False
    for path, rule in (
        (".env", "env-file"),
        ("cosign.key", "signing-key"),
        ("keys/cosign.private", "signing-key"),
        ("id_rsa", "ssh-key"),
    ):
        if rule not in [item[2] for item in name_findings(path)]:
            print(f"selftest: {path} was not refused")
            ok = False
    if name_findings("cosign.pub") or name_findings("keys/secureblue.pub") or name_findings(".env.example"):
        print("selftest: a public or example file was refused")
        ok = False
    print("secret scan selftest " + ("ok" if ok else "FAILED"))
    return 0 if ok else 1


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        return selftest()
    staged = "--staged" in argv
    paths = [arg for arg in argv if not arg.startswith("--")]
    if not paths:
        paths = git_files(staged)
    return report(scan(paths, staged))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
