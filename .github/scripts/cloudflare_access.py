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
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

POLICY_NAME = "unwoke-invite"
SEAT_CAP = 45


class CfError(Exception):
    pass


def domains_of(app: dict) -> list[str]:
    found: list[str] = []

    def add(value: object) -> None:
        if isinstance(value, str) and value.strip():
            found.append(value.strip())
        elif isinstance(value, dict):
            for key in ("domain", "hostname", "uri", "public_hostname"):
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


def _error_note(raw: bytes) -> str:
    """Cloudflare error code and a short message. Emails are not printed."""
    try:
        parsed = json.loads(raw.decode("utf-8", "replace"))
    except json.JSONDecodeError:
        return ""
    errors = parsed.get("errors") if isinstance(parsed, dict) else None
    if not isinstance(errors, list) or not errors or not isinstance(errors[0], dict):
        return ""
    code = errors[0].get("code")
    message = re.sub(r"\S+@\S+", "[email]", str(errors[0].get("message") or ""))
    message = " ".join(message.split())[:160]
    if code is None:
        return message
    return f"{code} {message}".strip()


def _request(method: str, url: str, token: str, body: dict | None = None) -> dict:
    data = None if body is None else json.dumps(body).encode()
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
        "User-Agent": "unwoke-invite",
    }
    # A GET with Content-Type: application/json and no body is HTTP 400.
    if data is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
            code = resp.status
    except urllib.error.HTTPError as exc:
        note = _error_note(exc.read())
        detail = f"cloudflare http {exc.code}"
        if note:
            detail = f"{detail}: {note}"
        raise CfError(detail) from None
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
    token = os.environ.get("CLOUDFLARE_API_TOKEN", "").strip()
    account = os.environ.get("CLOUDFLARE_ACCOUNT_ID", "").strip()
    domain = os.environ.get("CLOUDFLARE_ACCESS_DOMAIN", "").strip()
    if not token:
        raise CfError("skip")
    if not account or not domain:
        raise CfError("cloudflare account or domain is unset")
    if not re.fullmatch(r"[a-f0-9]{32}", account):
        raise CfError("cloudflare account id is not a 32-character id")
    return token, account, domain


def app_hosts(app: dict) -> set[str]:
    return {host_of(name) for name in domains_of(app)}


def select_app(apps: list[dict], domain: str) -> dict | None:
    """One application must list both the hostname and the preview wildcard."""
    apex = domain.lower().rstrip(".")
    want = {apex, f"*.{apex}"}
    for app in apps:
        if want <= app_hosts(app) and app.get("id"):
            return app
    return None


def policy_protects(policies: list[dict]) -> bool:
    """True only for the named Allow policy that names emails and not everyone."""
    for item in policies:
        if item.get("name") != POLICY_NAME or item.get("decision") != "allow":
            continue
        include = item.get("include")
        if not isinstance(include, list) or not include:
            continue
        if any(isinstance(rule, dict) and "everyone" in rule for rule in include):
            return False
        if any(isinstance(rule, dict) and isinstance(rule.get("email"), dict) for rule in include):
            return True
    return False


def list_apps(token: str, account: str) -> list[dict]:
    url = account_url(account, "/access/apps")
    try:
        payload = _request("GET", url + "?page=1&per_page=50", token)
    except CfError as exc:
        if "http 400" not in str(exc):
            raise
        payload = _request("GET", url, token)
    return _result_list(payload)


def find_app(token: str, account: str, domain: str) -> dict:
    apps = list_apps(token, account)
    app = select_app(apps, domain)
    if app is None:
        raise CfError("access application does not cover the site and its preview wildcard")
    return app


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
        app = find_app(token, account, domain)
        policies = _result_list(
            _request(
                "GET",
                account_url(account, f"/access/apps/{app['id']}/policies"),
                token,
            )
        )
    except CfError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    if not policy_protects(policies):
        print("access policy unwoke-invite does not limit the site", file=sys.stderr)
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


def count_seats(users: list[dict]) -> int | None:
    """Count Zero Trust seats. A seat is access_seat or gateway_seat.

    Returns None when the payload has no seat flags, so a user total is
    not treated as a seat total. Does not read emails.
    """
    saw = False
    used = 0
    for user in users:
        if not isinstance(user, dict):
            continue
        if "access_seat" not in user and "gateway_seat" not in user:
            continue
        saw = True
        if user.get("access_seat") or user.get("gateway_seat"):
            used += 1
    return used if saw else None


def fetch_seat_count(token: str, account: str) -> int | None:
    users: list[dict] = []
    page = 1
    total_pages = 1
    while page <= total_pages and page <= 5:
        payload = _request(
            "GET",
            account_url(account, f"/access/users?page={page}&per_page=1000"),
            token,
        )
        users.extend(_result_list(payload))
        info = payload.get("result_info")
        if isinstance(info, dict) and isinstance(info.get("total_pages"), int):
            total_pages = info["total_pages"]
        page += 1
    return count_seats(users)


def _alarm_seats(count: int) -> None:
    if not os.environ.get("GITHUB_REPOSITORY"):
        return
    alarm = Path(__file__).resolve().parent / "issue-alarm.sh"
    if not alarm.is_file():
        return
    import subprocess

    env = os.environ.copy()
    env["ALARM_EXTRA"] = (
        f"Seats in use: {count}. Free plan: 50. Guard: {SEAT_CAP}. "
        "Zero Trust → Users. Remove inactive seats. Do not buy a paid plan."
    )
    env["GH_TOKEN"] = env.get("GH_TOKEN") or env.get("GITHUB_TOKEN", "")
    cmd = "open" if count >= SEAT_CAP else "close"
    subprocess.run(["bash", str(alarm), "seats", cmd], check=False, env=env)


def report_seats() -> None:
    """Print seats=N or seats=unknown. Never prints a person."""
    token = os.environ.get("CLOUDFLARE_API_TOKEN", "").strip()
    account = os.environ.get("CLOUDFLARE_ACCOUNT_ID", "").strip()
    if not token or not account:
        print("seats=unknown")
        return
    try:
        count = fetch_seat_count(token, account)
    except CfError:
        print("seats=unknown")
        return
    if count is None:
        print("seats=unknown")
        return
    print(f"seats={count}")
    _alarm_seats(count)


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
    dest = [
        {
            "id": "dest",
            "destinations": [
                {"type": "public", "uri": "https://unwoke.pages.dev"},
                {"type": "public", "uri": "*.unwoke.pages.dev"},
            ],
        }
    ]
    if select_app(dest, "unwoke.pages.dev") is None:
        print("selftest FAIL destination coverage")
        ok = False
    split = [
        {"id": "apex", "domain": "unwoke.pages.dev"},
        {"id": "wild", "self_hosted_domains": ["*.unwoke.pages.dev"]},
    ]
    if select_app(split, "unwoke.pages.dev") is not None:
        print("selftest FAIL split apps")
        ok = False
    if not policy_protects(
        [{"name": POLICY_NAME, "decision": "allow", "include": [{"email": {"email": "a@example.com"}}]}]
    ):
        print("selftest FAIL protected policy")
        ok = False
    if policy_protects(
        [{"name": POLICY_NAME, "decision": "allow", "include": [{"everyone": {}}]}]
    ):
        print("selftest FAIL everyone policy")
        ok = False
    note = _error_note(
        b'{"errors":[{"code":7003,"message":"bad id for a@example.com"}]}'
    )
    if "7003" not in note or "@" in note:
        print("selftest FAIL error note")
        ok = False
    seated = count_seats(
        [
            {"access_seat": True, "email": "hidden@example.com"},
            {"gateway_seat": True},
            {"access_seat": False, "gateway_seat": False},
        ]
    )
    if seated != 2:
        print("selftest FAIL seat count")
        ok = False
    if count_seats([{"email": "hidden@example.com"}]) is not None:
        print("selftest FAIL seat guess")
        ok = False
    if SEAT_CAP != 45:
        print("selftest FAIL cap")
        ok = False
    print("cloudflare access selftest " + ("ok" if ok else "FAILED"))
    return 0 if ok else 1


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        return selftest()
    cmd = argv[1] if len(argv) > 1 else "check"
    if cmd == "check":
        return check()
    if cmd == "seats":
        report_seats()
        return 0
    print("usage: cloudflare_access.py check|seats|--selftest", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
