#!/usr/bin/env python3
"""Cloudflare Access gate for the docs site.

`check` refuses to publish unless an Access application covers the
pages.dev hostname and its preview wildcard. `sync` rewrites the
`unwoke-invite` Allow policy to the emails in memory. Responses that
might contain those emails are not printed.

    python3 .github/scripts/cloudflare_access.py --selftest
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

POLICY_NAME = "unwoke-invite"


class CfError(Exception):
    pass


def domains_of(app: dict) -> list[str]:
    found: list[str] = []

    def add(value: object) -> None:
        if isinstance(value, str) and value.strip():
            found.append(value.strip())
        elif isinstance(value, dict):
            for key in ("domain", "hostname", "uri"):
                if isinstance(value.get(key), str):
                    add(value[key])

    add(app.get("domain"))
    for key in ("self_hosted_domains", "destinations", "domains"):
        value = app.get(key)
        if isinstance(value, list):
            for item in value:
                add(item)
    return found


def host_of(value: str) -> str:
    text = value.strip().lower()
    if "://" in text:
        text = text.split("://", 1)[1]
    return text.split("/", 1)[0].rstrip(".")


def coverage(apps: list[dict], host: str) -> tuple[bool, bool]:
    hosts = {host_of(name) for app in apps for name in domains_of(app)}
    apex = host.lower().rstrip(".")
    return apex in hosts, f"*.{apex}" in hosts


def build_policy(emails: list[str], idp_id: str) -> dict:
    body: dict = {
        "name": POLICY_NAME,
        "decision": "allow",
        "include": [{"email": {"email": email}} for email in emails],
        "exclude": [],
    }
    if idp_id:
        body["require"] = [{"login_method": {"id": idp_id}}]
    return body


def _request(method: str, url: str, token: str, body: dict | None = None) -> dict:
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "User-Agent": "unwoke-invite",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
            code = resp.status
    except urllib.error.HTTPError as exc:
        exc.read()
        raise CfError(f"cloudflare http {exc.code}") from None
    except urllib.error.URLError:
        raise CfError("cloudflare unreachable") from None
    if code not in (200, 201):
        raise CfError(f"cloudflare http {code}")
    try:
        parsed = json.loads(raw.decode("utf-8", "replace"))
    except json.JSONDecodeError:
        raise CfError("cloudflare response was not json") from None
    if isinstance(parsed, dict) and parsed.get("success") is False:
        raise CfError("cloudflare rejected the request")
    return parsed if isinstance(parsed, dict) else {}


def _result_list(payload: dict) -> list[dict]:
    result = payload.get("result")
    if isinstance(result, list):
        return [item for item in result if isinstance(item, dict)]
    return []


def account_url(account: str, path: str) -> str:
    return f"https://api.cloudflare.com/client/v4/accounts/{account}{path}"


def require_env() -> tuple[str, str, str]:
    token = os.environ.get("CLOUDFLARE_API_TOKEN", "")
    account = os.environ.get("CLOUDFLARE_ACCOUNT_ID", "")
    domain = os.environ.get("CLOUDFLARE_ACCESS_DOMAIN", "")
    if not token:
        raise CfError("skip")
    if not account or not domain:
        raise CfError("cloudflare account or domain is unset")
    return token, account, domain


def find_app(token: str, account: str, domain: str) -> dict:
    payload = _request("GET", account_url(account, "/access/apps?per_page=100"), token)
    apps = _result_list(payload)
    apex, wild = coverage(apps, domain)
    if not apex or not wild:
        raise CfError("access application does not cover the site and its preview wildcard")
    want = {domain.lower().rstrip("."), f"*.{domain.lower().rstrip('.')}"}
    for app in apps:
        hosts = {host_of(name) for name in domains_of(app)}
        if want <= hosts and app.get("id"):
            return app
    for app in apps:
        hosts = {host_of(name) for name in domains_of(app)}
        if domain.lower().rstrip(".") in hosts and app.get("id"):
            return app
    raise CfError("access application id missing")


def check() -> int:
    try:
        token, account, domain = require_env()
    except CfError as exc:
        if str(exc) == "skip":
            print("deploy=skip")
            return 0
        print(str(exc), file=sys.stderr)
        return 1
    try:
        find_app(token, account, domain)
    except CfError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    print("deploy=go")
    return 0


def sync_emails(emails: list[str]) -> None:
    try:
        token, account, domain = require_env()
    except CfError as exc:
        if str(exc) == "skip":
            raise CfError("cloudflare token is unset") from None
        raise
    app = find_app(token, account, domain)
    app_id = str(app["id"])
    policies = _result_list(
        _request("GET", account_url(account, f"/access/apps/{app_id}/policies"), token)
    )
    idp = os.environ.get("CLOUDFLARE_GITHUB_IDP_ID", "").strip()
    body = build_policy(emails, idp)
    existing = next((item for item in policies if item.get("name") == POLICY_NAME), None)
    if existing and existing.get("id"):
        _request(
            "PUT",
            account_url(account, f"/access/apps/{app_id}/policies/{existing['id']}"),
            token,
            body,
        )
    else:
        _request(
            "POST",
            account_url(account, f"/access/apps/{app_id}/policies"),
            token,
            body,
        )
    print(f"cloudflare access policy updated ({len(emails)} emails)")


def selftest() -> int:
    ok = True
    apps = [
        {"id": "1", "domain": "unwoke.pages.dev", "self_hosted_domains": ["*.unwoke.pages.dev"]},
        {"id": "2", "domain": "other.example"},
    ]
    apex, wild = coverage(apps, "unwoke.pages.dev")
    if not apex or not wild:
        print("selftest FAIL coverage")
        ok = False
    apex, wild = coverage(apps, "missing.pages.dev")
    if apex or wild:
        print("selftest FAIL false coverage")
        ok = False
    policy = build_policy(["a@example.com"], "idp")
    if policy["decision"] != "allow" or policy["include"] != [{"email": {"email": "a@example.com"}}]:
        print("selftest FAIL policy")
        ok = False
    if "everyone" in json.dumps(policy):
        print("selftest FAIL everyone")
        ok = False
    if build_policy(["a@example.com"], "") .get("require"):
        print("selftest FAIL empty idp")
        ok = False
    print("cloudflare access selftest " + ("ok" if ok else "FAILED"))
    return 0 if ok else 1


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        return selftest()
    cmd = argv[1] if len(argv) > 1 else "check"
    if cmd == "check":
        return check()
    print("usage: cloudflare_access.py check|--selftest", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
