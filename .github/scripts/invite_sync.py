#!/usr/bin/env python3
"""Make GitHub collaborators match invite/allowlist.txt.

Only the repository owner may run this. It grants Read (permission pull)
and removes everyone else except the owner and bot accounts. It never
grants write, maintain, or admin. Usernames come from the allowlist file
on the branch that was checked out, not from a workflow input.

A copied PAT stops working once this login loses access: GHCR checks
permission when it issues a pull token. This script cannot delete an
image that person already pulled.

    python3 .github/scripts/invite_sync.py --selftest
    python3 .github/scripts/invite_sync.py audit
    python3 .github/scripts/invite_sync.py sync
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ALLOWLIST = ROOT / "invite" / "allowlist.txt"
USER_RE = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$")
READ_ROLES = frozenset({"read", "pull"})


class SyncError(Exception):
    pass


def parse_allowlist(text: str) -> list[str]:
    found: list[str] = []
    seen: set[str] = set()
    for number, raw in enumerate(text.splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        if not USER_RE.match(line):
            raise SyncError(f"allowlist line {number}: not a GitHub login")
        key = line.lower()
        if key in seen:
            raise SyncError(f"allowlist line {number}: duplicate {line}")
        seen.add(key)
        found.append(line)
    return found


def plan(owner: str, allow: list[str], collaborators: list[dict]) -> dict:
    owner_key = owner.lower()
    allow_keys = {name.lower(): name for name in allow}
    if owner_key in allow_keys:
        raise SyncError("the owner is implicit; remove that login from the allowlist")
    present: dict[str, str] = {}
    for row in collaborators:
        login = str(row.get("login") or "")
        role = str(row.get("role_name") or row.get("role") or "").lower()
        if not login:
            continue
        present[login.lower()] = role
    add = [name for key, name in allow_keys.items() if key not in present and key != owner_key]
    downgrade = []
    remove = []
    for login, role in present.items():
        if login == owner_key or login.endswith("[bot]"):
            continue
        if login not in allow_keys:
            remove.append(login)
            continue
        if role not in READ_ROLES:
            downgrade.append(login)
    return {
        "add": sorted(add, key=str.lower),
        "downgrade": sorted(downgrade),
        "remove": sorted(remove),
        "allow": sorted(allow_keys),
        "present": sorted(present),
    }


def anonymous_public(owner: str, name: str) -> str:
    """Return public, closed, or unknown. Never prints a token."""
    scope = f"repository:{owner}/{name}:pull"
    url = f"https://ghcr.io/token?service=ghcr.io&scope={scope}"
    try:
        with urllib.request.urlopen(url, timeout=20) as resp:
            body = json.loads(resp.read().decode("utf-8", "replace"))
        token = body.get("token") or ""
    except Exception:
        return "unknown"
    if not token:
        return "unknown"
    req = urllib.request.Request(
        f"https://ghcr.io/v2/{owner}/{name}/manifests/latest",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json",
            "User-Agent": "unwoke-invite-audit",
        },
        method="GET",
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            code = resp.status
    except urllib.error.HTTPError as exc:
        code = exc.code
    except Exception:
        return "unknown"
    if code == 200:
        return "public"
    if code in (401, 403, 404):
        return "closed"
    return "unknown"


def gh_raw(args: list[str]) -> str:
    res = subprocess.run(
        ["gh", "api", *args],
        check=False,
        capture_output=True,
        text=True,
    )
    if res.returncode != 0:
        err = (res.stderr or res.stdout or "").strip().splitlines()
        tail = err[-1] if err else "gh api failed"
        raise SyncError(tail[:300])
    return res.stdout


def gh_json(args: list[str]) -> object:
    text = gh_raw(args).strip()
    if not text:
        return None
    return json.loads(text)


def require_owner() -> tuple[str, str]:
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    actor = os.environ.get("GITHUB_ACTOR", "")
    owner = os.environ.get("GITHUB_REPOSITORY_OWNER", "")
    ref = os.environ.get("GITHUB_REF", "")
    event = os.environ.get("GITHUB_EVENT_NAME", "")
    if not repo or "/" not in repo:
        raise SyncError("GITHUB_REPOSITORY is unset")
    if actor.lower() != owner.lower():
        raise SyncError("refused: only the repository owner may grant or audit access")
    if ref != "refs/heads/main":
        raise SyncError("refused: invite-sync runs only on main")
    if event not in {"workflow_dispatch", "push", "schedule"}:
        raise SyncError(f"refused: event {event or 'unset'} cannot grant access")
    return repo, owner


def list_collaborators(repo: str) -> list[dict]:
    text = gh_raw(
        [
            "--paginate",
            f"repos/{repo}/collaborators",
            "--jq",
            ".[] | {login: .login, role_name: .role_name}",
        ]
    )
    rows = []
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        row = json.loads(line)
        if isinstance(row, dict):
            rows.append(row)
    return rows


def apply_plan(repo: str, decisions: dict, dry_run: bool) -> None:
    for login in decisions["remove"]:
        print(f"remove {login}")
        if dry_run:
            continue
        gh_json(["--method", "DELETE", f"repos/{repo}/collaborators/{login}"])
    for login in decisions["add"] + decisions["downgrade"]:
        print(f"grant read {login}")
        if dry_run:
            continue
        gh_json(
            [
                "--method",
                "PUT",
                f"repos/{repo}/collaborators/{login}",
                "-f",
                "permission=pull",
            ]
        )


def load_names() -> list[str]:
    path = ROOT / ".github" / "scripts" / "package-names.txt"
    names = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            names.append(line)
    return names


def audit_packages(owner: str) -> int:
    public = []
    unknown = []
    for name in load_names():
        state = anonymous_public(owner.lower(), name)
        print(f"package {name}: {state}")
        if state == "public":
            public.append(name)
        elif state == "unknown":
            unknown.append(name)
    if public:
        print(
            "ANOMALY: anonymous pull still works. A public package cannot be "
            "switched back to private. Delete it and let the bake create a new "
            "private package after the repository is private. See invite/OWNER-STEPS.md."
        )
    else:
        print(
            "No anonymous pull of the named packages. GitHub personal accounts "
            "do not report who pulled. Review https://github.com/settings/security-log "
            "for personal_access_token access and repo.add_member."
        )
    if unknown:
        print(f"package checks inconclusive: {', '.join(unknown)}")
    return 1 if public else 0


def token_present() -> bool:
    return bool(os.environ.get("GH_TOKEN") or os.environ.get("INVITE_ADMIN_TOKEN"))


def run(cmd: str) -> int:
    repo, owner = require_owner()
    allow = parse_allowlist(ALLOWLIST.read_text(encoding="utf-8"))
    # Anonymous-pull results are an owner task, not a failed grant.
    # The bake's package-visibility job opens the alarm.
    audit_packages(owner)
    if not token_present():
        if allow:
            raise SyncError(
                "INVITE_ADMIN_TOKEN is unset. Refusing to grant. "
                "Add the fine-grained admin token before anyone is listed."
            )
        print("invite-sync: allowlist empty and no admin token; collaborator API skipped")
        return 0
    collaborators = list_collaborators(repo)
    decisions = plan(owner, allow, collaborators)
    print(
        f"allow {len(decisions['allow'])}  "
        f"add {len(decisions['add'])}  "
        f"downgrade {len(decisions['downgrade'])}  "
        f"remove {len(decisions['remove'])}"
    )
    if len(collaborators) > len(allow) + 5:
        print(
            "ANOMALY: collaborator count is far above the allowlist. "
            "Review https://github.com/settings/security-log for repo.add_member."
        )
    drift = bool(decisions["add"] or decisions["downgrade"] or decisions["remove"])
    if cmd == "audit":
        if drift:
            print("drift: GitHub collaborators do not match invite/allowlist.txt")
        return 1 if drift else 0
    if cmd == "sync":
        dry = os.environ.get("INVITE_SYNC_DRY_RUN") == "1"
        apply_plan(repo, decisions, dry)
        return 0
    raise SyncError("usage: invite_sync.py audit|sync|--selftest")


def selftest() -> int:
    ok = True
    allow = parse_allowlist("# c\n\noctocat\n  Hubot  \n")
    if [name.lower() for name in allow] != ["octocat", "hubot"]:
        print("selftest FAIL parse")
        ok = False
    try:
        parse_allowlist("not a user\n")
        print("selftest FAIL bad login accepted")
        ok = False
    except SyncError:
        pass
    try:
        parse_allowlist("octocat\noctocat\n")
        print("selftest FAIL duplicate accepted")
        ok = False
    except SyncError:
        pass
    decisions = plan(
        "Owner",
        ["octocat", "hubot"],
        [
            {"login": "Owner", "role_name": "admin"},
            {"login": "octocat", "role_name": "write"},
            {"login": "stranger", "role_name": "read"},
            {"login": "dependabot[bot]", "role_name": "write"},
        ],
    )
    if decisions["add"] != ["hubot"] or decisions["downgrade"] != ["octocat"]:
        print(f"selftest FAIL plan add/downgrade {decisions}")
        ok = False
    if decisions["remove"] != ["stranger"]:
        print(f"selftest FAIL plan remove {decisions}")
        ok = False
    try:
        plan("Owner", ["owner"], [])
        print("selftest FAIL owner on allowlist accepted")
        ok = False
    except SyncError:
        pass
    empty = plan("Owner", [], [{"login": "octocat", "role_name": "read"}])
    if empty["remove"] != ["octocat"] or empty["add"]:
        print("selftest FAIL empty allowlist")
        ok = False
    print("invite sync selftest " + ("ok" if ok else "FAILED"))
    return 0 if ok else 1


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        return selftest()
    cmd = argv[1] if len(argv) > 1 else "audit"
    try:
        return run(cmd)
    except SyncError as exc:
        print(f"invite-sync: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
