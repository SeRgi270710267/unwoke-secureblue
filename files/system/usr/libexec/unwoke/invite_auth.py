#!/usr/bin/env python3
# Unwoke SecureBlue. Not affiliated with secureblue.
# SPDX-License-Identifier: LicenseRef-Unwoke-SA-1.0. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
"""Write /etc/ostree/auth.json for a private GHCR pull.

rpm-ostree and bootc read this file for registry credentials. It must be
root-owned mode 0600. The token is never printed and is never taken from
argv. GitHub Packages accepts a classic PAT; fine-grained tokens cannot
pull GHCR. The only accepted scope is read:packages.

    python3 invite_auth.py --selftest
    UNWOKE_INVITE_USER=... UNWOKE_INVITE_TOKEN=... python3 invite_auth.py save
    python3 invite_auth.py status
"""

from __future__ import annotations

import base64
import json
import os
import re
import stat
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

AUTH_FILE = Path(os.environ.get("UNWOKE_AUTH_FILE", "/etc/ostree/auth.json"))
IMAGE_REF_FILE = Path(os.environ.get("UNWOKE_IMAGE_REF_FILE", "/etc/unwoke/image-ref"))
REGISTRY = "ghcr.io"
USER_RE = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$")
ALLOWED_SCOPE = frozenset({"read:packages"})
TOKEN_PREFIX = "ghp_"


class InviteError(Exception):
    pass


def refuse_argv_token(argv: list[str]) -> None:
    for arg in argv:
        if "ghp_" in arg or "github_pat_" in arg or arg.startswith("github_pat"):
            raise InviteError("refused: a token was passed on the command line")


def parse_scopes(header: str | None) -> frozenset[str]:
    if header is None:
        return frozenset()
    parts = []
    for item in header.split(","):
        scope = item.strip().lower()
        if scope:
            parts.append(scope)
    return frozenset(parts)


def check_token_shape(user: str, token: str) -> None:
    if not USER_RE.match(user):
        raise InviteError("refused: GitHub username is not a single login")
    if not token or token != token.strip() or any(ch in token for ch in "\r\n\t "):
        raise InviteError("refused: token is empty or contains whitespace")
    if token.startswith("github_pat_"):
        raise InviteError(
            "refused: fine-grained tokens cannot pull GHCR. "
            "Create a classic PAT with only read:packages"
        )
    if not token.startswith(TOKEN_PREFIX):
        raise InviteError("refused: pull token must be a classic PAT (ghp_)")


def check_scopes(scopes: frozenset[str]) -> None:
    if scopes != ALLOWED_SCOPE:
        extra = ", ".join(sorted(scopes - ALLOWED_SCOPE)) or "(none)"
        raise InviteError(
            "refused: token scope must be exactly read:packages "
            f"(got extra or missing: {extra})"
        )


def auth_document(user: str, token: str) -> dict:
    check_token_shape(user, token)
    blob = base64.b64encode(f"{user}:{token}".encode()).decode("ascii")
    return {"auths": {REGISTRY: {"auth": blob}}}


def write_auth(path: Path, document: dict) -> None:
    path.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    os.chmod(path.parent, 0o755)
    payload = (json.dumps(document, indent=2) + "\n").encode()
    tmp = path.with_name(f".{path.name}.tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        os.write(fd, payload)
        os.fchmod(fd, 0o600)
    finally:
        os.close(fd)
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)
    os.chmod(path, 0o600)
    if hasattr(os, "chown") and hasattr(os, "geteuid") and os.geteuid() == 0:
        os.chown(path, 0, 0)


def file_status(path: Path) -> tuple[bool, str]:
    if not path.is_file():
        return False, "missing"
    mode = stat.S_IMODE(path.stat().st_mode)
    if mode != 0o600:
        return False, f"mode {mode:o} is not 600"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except PermissionError:
        # Mode is already 0600. A normal user cannot read the credential.
        return True, "mode 600"
    except (OSError, json.JSONDecodeError):
        return False, "unreadable"
    auth = data.get("auths", {}).get(REGISTRY, {}).get("auth")
    if not isinstance(auth, str) or len(auth) < 8:
        return False, "no ghcr.io credential"
    return True, "mode 600"


def _request(url: str, headers: dict[str, str]) -> tuple[int, dict[str, str], bytes]:
    req = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, {k.lower(): v for k, v in resp.headers.items()}, resp.read()
    except urllib.error.HTTPError as exc:
        body = exc.read() if exc.fp is not None else b""
        return exc.code, {k.lower(): v for k, v in exc.headers.items()}, body


def verify_scopes(token: str) -> None:
    code, headers, _body = _request(
        "https://api.github.com/user",
        {
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "User-Agent": "unwoke-invite-login",
        },
    )
    if code == 401:
        raise InviteError("refused: GitHub rejected the token")
    if code != 200:
        raise InviteError(f"refused: GitHub user API returned {code}")
    check_scopes(parse_scopes(headers.get("x-oauth-scopes")))


def split_image(ref: str) -> tuple[str, str, str]:
    raw = ref.strip()
    for prefix in (
        "ostree-image-signed:docker://",
        "ostree-unverified-registry:",
        "ostree-unverified-image:docker://",
        "docker://",
    ):
        if raw.startswith(prefix):
            raw = raw[len(prefix) :]
    if raw.startswith("https://"):
        raw = raw[len("https://") :]
    if "@" in raw:
        raw = raw.split("@", 1)[0]
    name, tag = (raw.rsplit(":", 1) if ":" in raw.split("/")[-1] else (raw, "latest"))
    parts = name.split("/")
    if len(parts) != 3 or parts[0] != REGISTRY or not parts[1] or not parts[2]:
        raise InviteError("refused: image ref must look like ghcr.io/owner/name:tag")
    return parts[1], parts[2], tag


def verify_pull(user: str, token: str, image_ref: str) -> str:
    owner, name, tag = split_image(image_ref)
    basic = base64.b64encode(f"{user}:{token}".encode()).decode("ascii")
    scope = f"repository:{owner}/{name}:pull"
    code, _headers, body = _request(
        f"https://ghcr.io/token?service=ghcr.io&scope={scope}",
        {"Authorization": f"Basic {basic}", "User-Agent": "unwoke-invite-login"},
    )
    if code != 200:
        raise InviteError(
            f"refused: registry token request returned {code}. "
            "The owner may not have granted this GitHub login Read"
        )
    try:
        bearer = json.loads(body.decode("utf-8", "replace")).get("token") or ""
    except json.JSONDecodeError:
        bearer = ""
    if not bearer:
        raise InviteError("refused: registry did not return a pull token")
    manifest_code, _mh, _mb = _request(
        f"https://ghcr.io/v2/{owner}/{name}/manifests/{tag}",
        {
            "Authorization": f"Bearer {bearer}",
            "Accept": "application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json",
            "User-Agent": "unwoke-invite-login",
        },
    )
    if manifest_code != 200:
        raise InviteError(
            f"refused: manifest request returned {manifest_code}. "
            "Read access is missing or the tag does not exist"
        )
    return f"pull ok {owner}/{name}:{tag}"


def detect_ref() -> str:
    env = os.environ.get("UNWOKE_IMAGE_REF", "").strip()
    if env:
        return env
    if IMAGE_REF_FILE.is_file():
        line = IMAGE_REF_FILE.read_text(encoding="utf-8").strip().splitlines()
        if line and line[0].strip():
            return line[0].strip()
    status = os.environ.get("UNWOKE_RPM_OSTREE_STATUS", "")
    if not status:
        return ""
    try:
        data = json.loads(status)
    except json.JSONDecodeError:
        return ""
    deployments = data.get("deployments") if isinstance(data, dict) else None
    if not isinstance(deployments, list):
        return ""
    for dep in deployments:
        if not isinstance(dep, dict):
            continue
        ref = dep.get("container-image-reference") or dep.get("origin") or ""
        if isinstance(ref, str) and "ghcr.io/" in ref:
            return ref
    return ""


def cmd_status() -> int:
    ok, detail = file_status(AUTH_FILE)
    # Detail is a mode or a short reason. Never the credential.
    print(f"invite: {detail}")
    return 0 if ok else 1


def cmd_save() -> int:
    user = os.environ.get("UNWOKE_INVITE_USER", "")
    token = os.environ.get("UNWOKE_INVITE_TOKEN", "")
    document = auth_document(user, token)
    if os.environ.get("UNWOKE_INVITE_SKIP_NET") != "1":
        verify_scopes(token)
        ref = detect_ref()
        if ref:
            print(verify_pull(user, token, ref))
        else:
            print("invite: no image ref to test; credential scope is read:packages")
    write_auth(AUTH_FILE, document)
    os.chmod(AUTH_FILE, 0o600)
    print(f"invite: wrote {AUTH_FILE} mode 600")
    return 0


def cmd_logout() -> int:
    if AUTH_FILE.is_file():
        AUTH_FILE.unlink()
        print("invite: removed local registry credential")
    else:
        print("invite: no local registry credential")
    return 0


def selftest() -> int:
    ok = True

    def check(label: str, fn) -> None:
        nonlocal ok
        try:
            fn()
        except Exception as exc:  # noqa: BLE001 - report and keep going
            print(f"selftest FAIL {label}: {exc}")
            ok = False

    def expect_error(label: str, fn) -> None:
        nonlocal ok
        try:
            fn()
        except InviteError:
            return
        print(f"selftest FAIL {label}: error was not raised")
        ok = False

    token = "ghp_" + ("a1" * 20)
    check("shape", lambda: check_token_shape("octocat", token))
    expect_error("fine-grained", lambda: check_token_shape("octocat", "github_pat_" + "ab" * 20))
    expect_error("space", lambda: check_token_shape("octocat", token + " "))
    expect_error("user", lambda: check_token_shape("-nope", token))
    check("scopes-ok", lambda: check_scopes(parse_scopes("read:packages")))
    check("scopes-space", lambda: check_scopes(parse_scopes(" read:packages ")))
    expect_error("scopes-repo", lambda: check_scopes(parse_scopes("read:packages, repo")))
    expect_error("scopes-write", lambda: check_scopes(parse_scopes("write:packages")))
    expect_error("scopes-empty", lambda: check_scopes(parse_scopes("")))
    doc = auth_document("octocat", token)
    raw = base64.b64decode(doc["auths"]["ghcr.io"]["auth"]).decode()
    if raw != f"octocat:{token}":
        print("selftest FAIL roundtrip")
        ok = False
    owner, name, tag = split_image(
        "ostree-image-signed:docker://ghcr.io/sergi270710267/unwoke-silverblue-trivalent:latest"
    )
    if (owner, name, tag) != ("sergi270710267", "unwoke-silverblue-trivalent", "latest"):
        print("selftest FAIL split")
        ok = False
    expect_error("argv", lambda: refuse_argv_token(["save", token]))
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "auth.json"
        write_auth(path, doc)
        mode = stat.S_IMODE(path.stat().st_mode)
        if mode != 0o600:
            print(f"selftest FAIL mode {mode:o}")
            ok = False
        good, _detail = file_status(path)
        if not good:
            print("selftest FAIL status")
            ok = False
        text = path.read_text(encoding="utf-8")
        if token in text or "octocat:" in text:
            print("selftest FAIL token stored in the clear")
            ok = False
    print("invite auth selftest " + ("ok" if ok else "FAILED"))
    return 0 if ok else 1


def main(argv: list[str]) -> int:
    try:
        refuse_argv_token(argv)
    except InviteError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    cmd = argv[1] if len(argv) > 1 else "status"
    try:
        if cmd == "--selftest":
            return selftest()
        if cmd == "status":
            return cmd_status()
        if cmd == "save":
            return cmd_save()
        if cmd == "logout":
            return cmd_logout()
        if cmd == "detect-ref":
            ref = detect_ref()
            if ref:
                print(ref)
            return 0
    except InviteError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    print("usage: invite_auth.py status|save|logout|detect-ref|--selftest", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
