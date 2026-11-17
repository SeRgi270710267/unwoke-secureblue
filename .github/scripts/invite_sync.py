#!/usr/bin/env python3
"""Read the invite list from the INVITE_ALLOWLIST secret.

The list is not a file in this public repository. Each line is
`github-login email`. This script prints only the count. It does not
add repository collaborators: on a public repository that would not
hide the code, and it would publish who was invited.

GitHub does not offer an API to grant package Read on a personal
account, so package Read stays a package-settings click. Cloudflare
Access emails are updated by cloudflare_access.py.

    python3 .github/scripts/invite_sync.py --selftest
"""

from __future__ import annotations

import os
import re
import sys

USER_RE = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$")
EMAIL_RE = re.compile(r"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$")
# Free Zero Trust plan is 50 seats. Stop at 45 so a sync cannot cross it.
SEAT_CAP = 45


class SyncError(Exception):
    pass


def parse_allowlist(text: str) -> list[tuple[str, str]]:
    found: list[tuple[str, str]] = []
    logins: set[str] = set()
    emails: set[str] = set()
    for number, raw in enumerate(text.splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) != 2:
            raise SyncError(f"allowlist line {number}: want login and email")
        login, email = parts
        if not USER_RE.match(login):
            raise SyncError(f"allowlist line {number}: login is not a GitHub login")
        if not EMAIL_RE.match(email):
            raise SyncError(f"allowlist line {number}: email is not usable")
        key = login.lower()
        mail = email.lower()
        if key in logins or mail in emails:
            raise SyncError(f"allowlist line {number}: duplicate")
        logins.add(key)
        emails.add(mail)
        found.append((login, email))
    return found


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        return selftest()
    raw = os.environ.get("INVITE_ALLOWLIST", "")
    try:
        rows = parse_allowlist(raw)
    except SyncError as exc:
        print(f"invite-sync: {exc}", file=sys.stderr)
        return 1
    count = len(rows)
    print(f"invite-sync: {count} entries")
    if count > SEAT_CAP:
        print(f"invite-sync: refused {count} entries, cap {SEAT_CAP}")
        return 1
    import cloudflare_access

    if not rows:
        print("invite-sync: secret empty; Cloudflare policy not changed")
    else:
        try:
            cloudflare_access.sync_emails([email for _login, email in rows])
        except cloudflare_access.CfError as exc:
            print(f"invite-sync: {exc}", file=sys.stderr)
            return 1
    cloudflare_access.report_seats()
    return 0


def selftest() -> int:
    ok = True
    rows = parse_allowlist("# c\n\noctocat user@example.com\n  Hubot  hubot@example.com \n")
    if [item[0].lower() for item in rows] != ["octocat", "hubot"]:
        print("selftest FAIL parse")
        ok = False
    try:
        parse_allowlist("octocat\n")
        print("selftest FAIL missing email accepted")
        ok = False
    except SyncError:
        pass
    try:
        parse_allowlist("octocat not-an-email\n")
        print("selftest FAIL bad email accepted")
        ok = False
    except SyncError:
        pass
    try:
        parse_allowlist("octocat a@example.com\nOctocat b@example.com\n")
        print("selftest FAIL duplicate login accepted")
        ok = False
    except SyncError:
        pass
    try:
        parse_allowlist("-bad a@example.com\n")
        print("selftest FAIL bad login accepted")
        ok = False
    except SyncError:
        pass
    many = "\n".join(f"user{i} u{i}@example.com" for i in range(SEAT_CAP + 1))
    if len(parse_allowlist(many)) <= SEAT_CAP:
        print("selftest FAIL cap fixture")
        ok = False
    if SEAT_CAP != 45:
        print("selftest FAIL cap value")
        ok = False
    print("invite sync selftest " + ("ok" if ok else "FAILED"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
