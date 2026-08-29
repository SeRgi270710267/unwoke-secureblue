#!/usr/bin/env python3
"""Vendor installer contracts. Used on the image and in CI. Does not auto-unlock."""
from __future__ import annotations

import json
import ssl
import sys
import urllib.error
import urllib.request
import re
from pathlib import Path
from urllib.parse import urljoin, urlparse

CTX = ssl.create_default_context()
HOSTS = frozenset(
    {
        "proton.me",
        "www.proton.me",
        "account.protonvpn.com",
        "protonvpn.com",
        "www.protonvpn.com",
        "repo.ivpn.net",
        "ivpn.net",
        "www.ivpn.net",
    }
)


def _repo_manifest() -> Path:
    usr = Path(__file__).resolve().parents[2]
    return usr / "share" / "unwoke" / "vendor-installers.json"


def load() -> dict:
    path = _repo_manifest()
    return json.loads(path.read_text(encoding="utf-8"))


def fetch(url: str, timeout: int = 30) -> bytes:
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "unwoke-vendor-check"},
        method="GET",
    )
    with urllib.request.urlopen(req, timeout=timeout, context=CTX) as resp:
        if resp.status != 200:
            raise RuntimeError(f"{url} HTTP {resp.status}")
        return resp.read()


def head_or_probe(url: str, timeout: int = 30) -> None:
    for method in ("HEAD", "GET"):
        req = urllib.request.Request(
            url,
            headers={"User-Agent": "unwoke-vendor-check", "Range": "bytes=0-64"},
            method=method,
        )
        try:
            with urllib.request.urlopen(req, timeout=timeout, context=CTX) as resp:
                if resp.status in (200, 206, 416):
                    return
                if method == "HEAD" and resp.status in (403, 405):
                    continue
                raise RuntimeError(f"{url} HTTP {resp.status}")
        except urllib.error.HTTPError as exc:
            if method == "HEAD" and exc.code in (403, 405, 501):
                continue
            if exc.code in (200, 206):
                return
            raise RuntimeError(f"{url} HTTP {exc.code}") from exc
    raise RuntimeError(f"{url} not reachable")


def pick_rpm_from_json(blob: bytes) -> tuple[str, str, str]:
    data = json.loads(blob)
    releases = data.get("Releases") or data.get("releases") or []
    order = ("Stable", "EarlyAccess", "Alpha")
    for cat in order:
        for rel in releases:
            if (rel.get("CategoryName") or rel.get("categoryName") or "") != cat:
                continue
            for f in rel.get("File") or rel.get("file") or []:
                ident = str(f.get("Identifier") or "") + " " + str(f.get("Url") or f.get("url") or "")
                url = f.get("Url") or f.get("url") or ""
                sha = f.get("Sha512CheckSum") or f.get("sha512") or f.get("Sha512") or ""
                if "rpm" not in ident.lower() and not str(url).lower().endswith(".rpm"):
                    continue
                if url and sha:
                    ver = str(rel.get("Version") or rel.get("version") or "")
                    return ver, str(url), str(sha)
    raise RuntimeError("no RPM + SHA512 in version.json (schema changed?)")


def check_yum_repo(text: str, require_gpg: bool) -> None:
    low = text.lower()
    if "baseurl=" not in low and "metalink=" not in low:
        raise RuntimeError("repo file has no baseurl/metalink")
    if "http://" in text and "https://" not in text:
        raise RuntimeError("repo file looks HTTP-only")
    if require_gpg and "gpgcheck=0" in low.replace(" ", ""):
        raise RuntimeError("repo sets gpgcheck=0")
    if require_gpg and "gpgcheck=1" not in low.replace(" ", ""):
        raise RuntimeError("repo missing gpgcheck=1")


def check_one(name: str, spec: dict, probe_rpm: bool) -> str:
    kind = spec.get("kind")
    if kind == "https-ok":
        url = spec["url"]
        head_or_probe(url)
        return f"ok  {name}  {url}"
    if kind == "yum-repo":
        url = spec["url"]
        body = fetch(url).decode("utf-8", errors="replace")
        check_yum_repo(body, bool(spec.get("require_gpgcheck")))
        return f"ok  {name}  {url}"
    if kind == "proton-version-json":
        last = None
        for url in spec.get("json_urls") or []:
            try:
                blob = fetch(url)
                ver, rpm, sha = pick_rpm_from_json(blob)
                if len(sha) < 64:
                    raise RuntimeError("SHA512 too short")
                if probe_rpm:
                    head_or_probe(rpm)
                return f"ok  {name}  {ver}  {rpm}"
            except Exception as exc:
                last = exc
                continue
        raise RuntimeError(f"{name}: {last}")
    raise RuntimeError(f"{name}: unknown kind {kind}")


def cmd_pick(name: str) -> int:
    spec = load()["vendors"][name]
    last = None
    for url in spec.get("json_urls") or []:
        try:
            ver, rpm, sha = pick_rpm_from_json(fetch(url))
            sys.stdout.write(f"{ver}\n{rpm}\n{sha}\n")
            return 0
        except Exception as exc:
            last = exc
    print(f"FAIL pick {name}: {last}", file=sys.stderr)
    return 1


def cmd_url(name: str) -> int:
    spec = load()["vendors"][name]
    u = spec.get("url") or (spec.get("json_urls") or [""])[0]
    sys.stdout.write(u + "\n")
    return 0 if u else 1


def allowed(url: str) -> bool:
    p = urlparse(url)
    return p.scheme == "https" and (p.hostname or "") in HOSTS


def extract_urls(html: str, base: str) -> list[str]:
    found: list[str] = []
    for m in re.finditer(r"https://[^\s\"'<>]+", html):
        u = m.group(0).rstrip(".,);")
        if allowed(u):
            found.append(u)
    for m in re.finditer(r"""href=["']([^"']+)["']""", html, re.I):
        u = urljoin(base, m.group(1))
        if allowed(u):
            found.append(u)
    out: list[str] = []
    seen: set[str] = set()
    for u in found:
        if u not in seen:
            seen.add(u)
            out.append(u)
    return out


def docs_urls(spec: dict) -> list[str]:
    docs = spec.get("docs") or spec.get("heal_docs") or ""
    extra = list(spec.get("heal_urls") or [])
    urls = ([docs] if docs else []) + extra
    scraped: list[str] = []
    for d in urls:
        if not allowed(d):
            continue
        try:
            html = fetch(d).decode("utf-8", errors="replace")
            scraped.extend(extract_urls(html, d))
        except Exception:
            continue
    return scraped


def try_heal(name: str, spec: dict, probe_rpm: bool) -> tuple[dict | None, str]:
    kind = spec.get("kind")
    discovered = docs_urls(spec)
    if kind == "proton-version-json":
        cands = list(spec.get("json_urls") or []) + [
            u for u in discovered if "version.json" in u or u.endswith(".json")
        ]
        seen: set[str] = set()
        ordered: list[str] = []
        for u in cands:
            if allowed(u) and u not in seen:
                seen.add(u)
                ordered.append(u)
        for u in ordered:
            try:
                blob = fetch(u)
                ver, rpm, sha = pick_rpm_from_json(blob)
                if len(sha) < 64:
                    continue
                if probe_rpm:
                    head_or_probe(rpm)
                new = dict(spec)
                rest = [x for x in ordered if x != u]
                new["json_urls"] = [u] + rest
                return new, f"{ver} via {u}"
            except Exception:
                continue
        return None, ""
    if kind == "yum-repo":
        cands = [spec.get("url") or ""] + [
            u for u in discovered if u.endswith(".repo")
        ]
        for u in cands:
            if not allowed(u):
                continue
            try:
                body = fetch(u).decode("utf-8", errors="replace")
                check_yum_repo(body, bool(spec.get("require_gpgcheck")))
                new = dict(spec)
                new["url"] = u
                return new, u
            except Exception:
                continue
        return None, ""
    if kind == "https-ok":
        cands = [spec.get("url") or ""] + discovered
        for u in cands:
            if not allowed(u):
                continue
            try:
                head_or_probe(u)
                new = dict(spec)
                new["url"] = u
                return new, u
            except Exception:
                continue
        return None, ""
    return None, ""


def cmd_heal(probe_rpm: bool) -> int:
    path = _repo_manifest()
    data = load()
    dirty = False
    still = 0
    for name, spec in list(data.get("vendors", {}).items()):
        try:
            print(check_one(name, spec, probe_rpm))
            continue
        except Exception as exc:
            print(f"heal {name}: broken ({exc})", file=sys.stderr)
        new_spec, msg = try_heal(name, spec, probe_rpm)
        if new_spec:
            data["vendors"][name] = new_spec
            dirty = True
            print(f"healed {name}: {msg}")
        else:
            still += 1
            print(f"FAIL {name}: no allowlisted HTTPS replacement", file=sys.stderr)
    if dirty:
        path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        print(f"wrote {path}")
    if still:
        print(
            f"{still} vendor(s) still broken. Policy change (Flathub, gpgcheck=0, new schema) needs a human.",
            file=sys.stderr,
        )
        return 1
    print("all vendor contracts ok")
    return 0


def cmd_check(probe_rpm: bool) -> int:
    vendors = load()["vendors"]
    failed = 0
    for name, spec in vendors.items():
        try:
            print(check_one(name, spec, probe_rpm))
        except Exception as exc:
            print(f"FAIL {name}: {exc}", file=sys.stderr)
            failed += 1
    if failed:
        print(
            f"{failed} vendor contract(s) broken. Run: vendor.py heal --probe-rpm "
            "(CI does this; only HTTPS allowlisted hosts, still need SHA512/gpgcheck).",
            file=sys.stderr,
        )
        return 1
    print("all vendor contracts ok")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(
            "usage: vendor.py check [--probe-rpm] | heal [--probe-rpm] | pick NAME | url NAME",
            file=sys.stderr,
        )
        return 2
    cmd = argv[1]
    probe = "--probe-rpm" in argv
    if cmd == "check":
        return cmd_check(probe)
    if cmd == "heal":
        return cmd_heal(probe)
    if cmd == "pick" and len(argv) >= 3:
        return cmd_pick(argv[2])
    if cmd == "url" and len(argv) >= 3:
        return cmd_url(argv[2])
    print(
        "usage: vendor.py check [--probe-rpm] | heal [--probe-rpm] | pick NAME | url NAME",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
