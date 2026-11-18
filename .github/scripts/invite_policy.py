#!/usr/bin/env python3
"""Fail the PR gate if a public publish path comes back.

Does not decide who is invited. It only checks that this tree does not
tell the factory to make packages public, upload an ISO to GHCR, attach
digests to the receipt release, or put install commands on the public
README or the Pages notice.

    python3 .github/scripts/invite_policy.py
    python3 .github/scripts/invite_policy.py --selftest
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

PUBLIC_SURFACES = (
    "README.md",
    "site-notice/index.html",
)
LEAK_RE = re.compile(r"ghcr\.io/sergi270710267|rpm-ostree rebase", re.I)
R2_PUBLIC_RE = re.compile(r"https://\S*r2\.dev", re.I)


def problems_in_text(name: str, text: str) -> list[str]:
    found = []
    if name in PUBLIC_SURFACES or name.endswith("site-notice/index.html"):
        if LEAK_RE.search(text):
            found.append(f"{name}: public surface still has an install ref")
    if name.endswith("package-visibility.sh") or name.endswith("public-packages.sh"):
        if re.search(r"visibility=public", text):
            found.append(f"{name}: still sets package visibility public")
    if name.endswith("publish-receipt.sh"):
        if "gh release upload" in text or "DIGESTS.txt" in text:
            found.append(f"{name}: still publishes a digest receipt")
    if name.endswith("iso.yml"):
        if "upload-artifact" in text:
            found.append(f"{name}: ISO must not be an Actions artifact")
    if name.endswith("pages.yml"):
        if re.search(r"(?m)^\s*path:\s*docs\s*$", text):
            found.append(f"{name}: Pages still uploads docs/")
        if "site-notice" not in text:
            found.append(f"{name}: Pages does not deploy the notice")
        # The action or the pinned wrangler CLI. A comment that only names
        # wrangler is not a deploy.
        wrangler_cli = (
            "wrangler@" in text
            and re.search(r"\bpages\b", text)
            and re.search(r"\bdeploy\b", text)
            and re.search(r"\bdocs\b", text)
        )
        if "cloudflare/wrangler-action" not in text and not wrangler_cli:
            found.append(f"{name}: gated site deploy is missing")
    if name.endswith("build.yml"):
        if "attest-build-provenance" in text:
            found.append(f"{name}: still publishes public build provenance")
    if name.endswith("invite-sync.yml"):
        if re.search(r"(?m)^[\s-]*(pull_request|pull_request_target):", text):
            found.append(f"{name}: invite-sync must not run on pull requests")
        if "permission=push" in text or "permission=admin" in text or "collaborators/" in text:
            found.append(f"{name}: invite-sync must not grant repository access")
    if name.endswith("auth.json"):
        found.append(f"{name}: a registry credential file must not be tracked")
    return found


def scan_tree(root: Path) -> list[str]:
    found = []
    targets = [
        root / "README.md",
        root / "site-notice" / "index.html",
        root / ".github" / "scripts" / "package-visibility.sh",
        root / ".github" / "scripts" / "public-packages.sh",
        root / "docs" / "_tools" / "publish-receipt.sh",
        root / ".github" / "workflows" / "iso.yml",
        root / ".github" / "workflows" / "pages.yml",
        root / ".github" / "workflows" / "build.yml",
        root / ".github" / "workflows" / "invite-sync.yml",
    ]
    for path in targets:
        if not path.is_file():
            found.append(f"{path.relative_to(root)}: missing")
            continue
        rel = str(path.relative_to(root)).replace("\\", "/")
        found.extend(problems_in_text(rel, path.read_text(encoding="utf-8")))
    if (root / "invite" / "allowlist.txt").exists():
        found.append("invite/allowlist.txt must not be committed; logins belong in the INVITE_ALLOWLIST secret")
    iso_fn = root / "functions" / "iso" / "[[path]].js"
    if not iso_fn.is_file():
        found.append("functions/iso/[[path]].js: missing")
    elif R2_PUBLIC_RE.search(iso_fn.read_text(encoding="utf-8")):
        found.append("functions/iso: public r2.dev URL")
    wrangler = root / "wrangler.toml"
    if wrangler.is_file() and R2_PUBLIC_RE.search(wrangler.read_text(encoding="utf-8")):
        found.append("wrangler.toml: public r2.dev URL")
    for path in root.rglob("auth.json"):
        if path.is_file() and ".git" not in path.parts:
            found.append(f"{path.relative_to(root)}: a registry credential file must not be tracked")
    return found


def selftest() -> int:
    ok = True
    if problems_in_text("README.md", "See the repository."):
        print("selftest: a clean README was refused")
        ok = False
    if not problems_in_text("README.md", "rpm-ostree rebase ostree-unverified-registry:ghcr.io/sergi270710267/x"):
        print("selftest: an install line was accepted")
        ok = False
    if not problems_in_text("site-notice/index.html", "ghcr.io/sergi270710267/name"):
        print("selftest: a notice leak was accepted")
        ok = False
    if not problems_in_text("public-packages.sh", "visibility=public"):
        print("selftest: a public flip was accepted")
        ok = False
    if problems_in_text("package-visibility.sh", "never set visibility to private from CI"):
        print("selftest: a comment was refused")
        ok = False
    if not problems_in_text("iso.yml", "uses: actions/upload-artifact@abc # v4\n"):
        print("selftest: a public ISO artifact was accepted")
        ok = False
    if problems_in_text("iso.yml", "run: bash .github/scripts/publish-iso.sh\n"):
        print("selftest: a private ISO publish was refused")
        ok = False
    if not problems_in_text("pages.yml", "path: docs\n"):
        print("selftest: a docs upload was accepted")
        ok = False
    notice = "path: site-notice\nuses: cloudflare/wrangler-action@abc # v4.1.3\n"
    if problems_in_text("pages.yml", notice):
        print("selftest: the notice upload was refused")
        print(problems_in_text("pages.yml", notice))
        ok = False
    direct = "path: site-notice\nnpx wrangler@4.164.0 pages deploy docs\n"
    if problems_in_text("pages.yml", direct):
        print("selftest: a wrangler CLI deploy was refused")
        print(problems_in_text("pages.yml", direct))
        ok = False
    if not any(
        item.endswith("gated site deploy is missing")
        for item in problems_in_text("pages.yml", "path: site-notice\nwrangler is mentioned\n")
    ):
        print("selftest: a missing deploy was accepted")
        ok = False
    if not problems_in_text("publish-receipt.sh", "gh release upload receipt DIGESTS.txt\n"):
        print("selftest: a receipt upload was accepted")
        ok = False
    if not problems_in_text("build.yml", "uses: actions/attest-build-provenance@abc\n"):
        print("selftest: provenance publish was accepted")
        ok = False
    if not problems_in_text("invite-sync.yml", "on:\n  pull_request:\n"):
        print("selftest: a pull_request grant workflow was accepted")
        ok = False
    if not R2_PUBLIC_RE.search("fetch('https://pub-abc.r2.dev/latest.iso')"):
        print("selftest: a public r2 hostname was accepted")
        ok = False
    if R2_PUBLIC_RE.search("Do not add an r2.dev hostname."):
        print("selftest: a warning was refused")
        ok = False
    print("invite policy selftest " + ("ok" if ok else "FAILED"))
    return 0 if ok else 1


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        return selftest()
    found = scan_tree(ROOT)
    if found:
        print("invite policy: FAIL")
        for item in found:
            print(item)
        return 1
    print("invite policy: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
