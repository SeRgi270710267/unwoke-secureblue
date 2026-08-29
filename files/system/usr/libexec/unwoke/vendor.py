#!/usr/bin/env python3
"""Vendor installer contracts. Image + CI. Heal legit upstream changes only."""
from __future__ import annotations

import json
import os
import re
import ssl
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from urllib.parse import urljoin, urlparse

CTX = ssl.create_default_context()
HOSTS = frozenset(
    {
        "proton.me",
        "www.proton.me",
        "mail.proton.me",
        "pass.proton.me",
        "account.proton.me",
        "account.protonvpn.com",
        "protonvpn.com",
        "www.protonvpn.com",
        "repo.ivpn.net",
        "ivpn.net",
        "www.ivpn.net",
        "mullvad.net",
        "www.mullvad.net",
        "repository.mullvad.net",
    }
)
KINDS = frozenset(
    {"https-ok", "wireguard-import", "proton-version-json", "yum-repo"}
)
TRANSIENT_HTTP = frozenset({429, 500, 502, 503, 504})


class Transient(Exception):
    """Timeouts / 5xx / 429 — retry, do not rewrite the vendor list."""


def _repo_manifest() -> Path:
    env = os.environ.get("UNWOKE_VENDOR_JSON")
    if env:
        return Path(env)
    usr = Path(__file__).resolve().parents[2]
    return usr / "share" / "unwoke" / "vendor-installers.json"


def load() -> dict:
    return json.loads(_repo_manifest().read_text(encoding="utf-8"))


def allowed(url: str) -> bool:
    p = urlparse(url)
    return p.scheme == "https" and (p.hostname or "") in HOSTS


def fetch(url: str, timeout: int = 30) -> tuple[bytes, str]:
    last: Exception | None = None
    for attempt in range(4):
        req = urllib.request.Request(
            url,
            headers={"User-Agent": "unwoke-vendor-check"},
            method="GET",
        )
        try:
            with urllib.request.urlopen(req, timeout=timeout, context=CTX) as resp:
                if resp.status in TRANSIENT_HTTP:
                    last = Transient(f"{url} HTTP {resp.status}")
                    time.sleep(1.2 * (attempt + 1))
                    continue
                if resp.status != 200:
                    raise RuntimeError(f"{url} HTTP {resp.status}")
                final = resp.geturl() or url
                if not allowed(final):
                    raise RuntimeError(f"redirect left allowlist: {final}")
                data = resp.read()
                if data.startswith(b"\xef\xbb\xbf"):
                    data = data[3:]
                return data, final
        except Transient:
            raise
        except urllib.error.HTTPError as exc:
            if exc.code in TRANSIENT_HTTP:
                last = Transient(f"{url} HTTP {exc.code}")
                time.sleep(1.2 * (attempt + 1))
                continue
            raise RuntimeError(f"{url} HTTP {exc.code}") from exc
        except (TimeoutError, urllib.error.URLError, OSError) as exc:
            last = Transient(f"{url} {exc}")
            time.sleep(1.2 * (attempt + 1))
    if last:
        raise last
    raise Transient(f"{url} failed")


def head_or_probe(url: str, timeout: int = 30) -> None:
    last: Exception | None = None
    for method in ("HEAD", "GET"):
        req = urllib.request.Request(
            url,
            headers={"User-Agent": "unwoke-vendor-check", "Range": "bytes=0-64"},
            method=method,
        )
        try:
            with urllib.request.urlopen(req, timeout=timeout, context=CTX) as resp:
                if resp.status in TRANSIENT_HTTP:
                    last = Transient(f"{url} HTTP {resp.status}")
                    continue
                if resp.status in (200, 206, 416):
                    return
                if method == "HEAD" and resp.status in (403, 405, 501):
                    continue
                raise RuntimeError(f"{url} HTTP {resp.status}")
        except urllib.error.HTTPError as exc:
            if exc.code in TRANSIENT_HTTP:
                last = Transient(f"{url} HTTP {exc.code}")
                continue
            if method == "HEAD" and exc.code in (403, 405, 501):
                continue
            if exc.code in (200, 206):
                return
            raise RuntimeError(f"{url} HTTP {exc.code}") from exc
        except (TimeoutError, urllib.error.URLError, OSError) as exc:
            last = Transient(f"{url} {exc}")
            continue
    if last:
        raise last
    raise RuntimeError(f"{url} not reachable")


def _sha_field(obj: dict) -> str:
    for k, v in obj.items():
        lk = str(k).lower().replace("_", "")
        if "sha512" in lk or lk in ("sha512checksum", "checksumsha512"):
            s = str(v).strip().lower()
            h = re.search(r"[a-f0-9]{128}", s)
            if h:
                return h.group(0)
        if "sha256" in lk or lk in ("sha256checksum", "checksumsha256"):
            s = str(v).strip().lower()
            h = re.search(r"[a-f0-9]{64}", s)
            if h:
                return h.group(0)
    return ""


def _looks_rpm(ident: str, url: str) -> bool:
    blob = (ident + " " + url).lower()
    if ".deb" in blob and ".rpm" not in blob:
        return False
    return ".rpm" in blob or "fedora" in blob or "rhel" in blob


def sidecar_sha(rpm_url: str) -> str:
    for suf in (".sha512", ".sha512sum", ".SHA512", ".sha256", ".sha256sum"):
        try:
            txt, _ = fetch(rpm_url + suf)
            s = txt.decode("utf-8", errors="replace").lower()
            h = re.search(r"\b[a-f0-9]{128}\b", s) or re.search(r"\b[a-f0-9]{64}\b", s)
            if h:
                return h.group(0)
        except Exception:
            continue
    return ""


def pick_rpm_from_json(blob: bytes) -> tuple[str, str, str]:
    text = blob.decode("utf-8", errors="replace").strip()
    if text[:1] not in "{[":
        m = re.search(r"(\{.*\}|\[.*\])", text, re.S)
        if not m:
            raise RuntimeError("body is not JSON")
        text = m.group(1)
    data = json.loads(text)
    found: list[tuple[int, str, str, str]] = []

    def walk(obj: object, ver: str, rank: int) -> None:
        if isinstance(obj, dict):
            cat = str(obj.get("CategoryName") or obj.get("categoryName") or obj.get("channel") or "")
            r = {"stable": 0, "earlyaccess": 1, "alpha": 2, "beta": 3}.get(cat.lower(), rank)
            ver2 = str(obj.get("Version") or obj.get("version") or obj.get("tag") or ver)
            url = obj.get("Url") or obj.get("url") or obj.get("href") or obj.get("Href") or ""
            ident = str(obj.get("Identifier") or obj.get("identifier") or obj.get("name") or "")
            sha = _sha_field(obj)
            if url and _looks_rpm(ident, str(url)):
                if not sha:
                    sha = sidecar_sha(str(url))
                if sha and allowed(str(url)):
                    found.append((r, ver2, str(url), sha))
            for v in obj.values():
                walk(v, ver2, r)
        elif isinstance(obj, list):
            for i in obj:
                walk(i, ver, rank)

    walk(data, "", 9)
    if not found:
        raise RuntimeError("no RPM + SHA512/SHA256 in JSON (or sidecar)")
    found.sort(key=lambda t: t[0])
    _, ver, url, sha = found[0]
    return ver, url, sha


def check_yum_repo(text: str, require_gpg: bool) -> None:
    low = text.lower().replace(" ", "")
    if "baseurl=" not in low and "metalink=" not in low:
        raise RuntimeError("repo file has no baseurl/metalink")
    if re.search(r"baseurl=http://", text, re.I) and "https://" not in text.lower():
        raise RuntimeError("repo file looks HTTP-only")
    if require_gpg and "gpgcheck=0" in low:
        raise RuntimeError("repo sets gpgcheck=0")
    if require_gpg and "gpgcheck=1" not in low and "repo_gpgcheck=1" not in low:
        raise RuntimeError("repo missing gpgcheck=1")
    for m in re.finditer(r"gpgkey=(\S+)", text, re.I):
        k = m.group(1).strip()
        if k.startswith("http://"):
            raise RuntimeError("gpgkey is HTTP")
        if k.startswith("https://") and not allowed(k):
            raise RuntimeError(f"gpgkey left allowlist: {k}")


def check_schema(name: str, spec: dict) -> None:
    kind = spec.get("kind")
    if kind not in KINDS:
        raise RuntimeError(f"unknown kind {kind!r}")
    if not (spec.get("title") or "").strip():
        raise RuntimeError("missing title")
    if kind in ("https-ok", "wireguard-import", "yum-repo"):
        url = spec.get("url") or ""
        if not url:
            raise RuntimeError("missing url")
        if not allowed(url):
            raise RuntimeError(f"url not allowlisted: {url}")
    if kind == "proton-version-json":
        urls = spec.get("json_urls") or []
        if not urls:
            raise RuntimeError("missing json_urls")
        for u in urls:
            if not allowed(u):
                raise RuntimeError(f"json url not allowlisted: {u}")
    if kind == "yum-repo" and spec.get("require_gpgcheck") is not True:
        raise RuntimeError("yum-repo must set require_gpgcheck: true")
    docs = spec.get("docs") or spec.get("heal_docs") or ""
    if docs and not allowed(docs):
        raise RuntimeError(f"docs url not allowlisted: {docs}")
    for u in spec.get("heal_urls") or []:
        if not allowed(u):
            raise RuntimeError(f"heal url not allowlisted: {u}")


def cmd_schema() -> int:
    vendors = load().get("vendors") or {}
    if not vendors:
        print("FAIL: vendors{} empty", file=sys.stderr)
        return 1
    failed = 0
    for name, spec in vendors.items():
        try:
            check_schema(name, spec)
            print(f"ok  schema  {name}")
        except Exception as exc:
            print(f"FAIL schema {name}: {exc}", file=sys.stderr)
            failed += 1
    if failed:
        print(
            f"{failed} vendor schema error(s). Add an allowlisted host in vendor.py HOSTS "
            "only if you intend to trust it. Do not add Flathub.",
            file=sys.stderr,
        )
        return 1
    print(f"schema ok ({len(vendors)} vendors)")
    return 0


def check_one(name: str, spec: dict, probe_rpm: bool) -> str:
    check_schema(name, spec)
    kind = spec.get("kind")
    if kind in ("https-ok", "wireguard-import"):
        url = spec["url"]
        head_or_probe(url)
        return f"ok  {name}  {url}"
    if kind == "yum-repo":
        url = spec["url"]
        body, final = fetch(url)
        check_yum_repo(body.decode("utf-8", errors="replace"), bool(spec.get("require_gpgcheck")))
        return f"ok  {name}  {final}"
    if kind == "proton-version-json":
        last: Exception | None = None
        trans = 0
        for url in spec.get("json_urls") or []:
            try:
                blob, final = fetch(url)
                ver, rpm, sha = pick_rpm_from_json(blob)
                if len(sha) < 64:
                    raise RuntimeError("checksum too short")
                if probe_rpm:
                    head_or_probe(rpm)
                return f"ok  {name}  {ver}  {rpm}  (from {final})"
            except Transient as exc:
                last = exc
                trans += 1
                continue
            except Exception as exc:
                last = exc
                continue
        if trans and last:
            raise last
        raise RuntimeError(f"{name}: {last}")
    raise RuntimeError(f"{name}: unknown kind {kind}")


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
    scraped: list[str] = []
    for d in ([docs] if docs else []) + extra:
        if not allowed(d):
            continue
        try:
            html, final = fetch(d)
            scraped.extend(extract_urls(html.decode("utf-8", errors="replace"), final))
        except Exception:
            continue
    return scraped


def alt_hosts(url: str) -> list[str]:
    p = urlparse(url)
    host = p.hostname or ""
    alts = []
    if host.startswith("www."):
        alts.append(url.replace("https://www.", "https://", 1))
    elif host:
        alts.append(url.replace(f"https://{host}", f"https://www.{host}", 1))
    if url.endswith("/"):
        alts.append(url.rstrip("/"))
    else:
        alts.append(url + "/")
    return [u for u in alts if allowed(u) and u != url]


def try_heal(name: str, spec: dict, probe_rpm: bool) -> tuple[dict | None, str]:
    kind = spec.get("kind")
    discovered = docs_urls(spec)
    if kind == "proton-version-json":
        cands = list(spec.get("json_urls") or [])
        for u in list(cands):
            cands.extend(alt_hosts(u))
        cands.extend(
            u
            for u in discovered
            if "version.json" in u or u.endswith(".json") or "download" in u.lower()
        )
        seen: set[str] = set()
        ordered: list[str] = []
        for u in cands:
            if allowed(u) and u not in seen:
                seen.add(u)
                ordered.append(u)
        for u in ordered:
            try:
                blob, final = fetch(u)
                ver, rpm, sha = pick_rpm_from_json(blob)
                if len(sha) < 64:
                    continue
                if probe_rpm:
                    head_or_probe(rpm)
                new = dict(spec)
                rest = [x for x in ordered if x not in (u, final)]
                new["json_urls"] = [final] + rest
                return new, f"{ver} via {final}"
            except Transient:
                continue
            except Exception:
                continue
        return None, ""
    if kind == "yum-repo":
        cands = [spec.get("url") or ""] + alt_hosts(spec.get("url") or "")
        cands.extend(u for u in discovered if u.endswith(".repo") or ".repo?" in u)
        for u in cands:
            if not allowed(u):
                continue
            try:
                body, final = fetch(u)
                check_yum_repo(body.decode("utf-8", errors="replace"), bool(spec.get("require_gpgcheck")))
                new = dict(spec)
                new["url"] = final
                return new, final
            except Transient:
                continue
            except Exception:
                continue
        return None, ""
    if kind in ("https-ok", "wireguard-import"):
        cands = [spec.get("url") or ""] + alt_hosts(spec.get("url") or "") + discovered
        for u in cands:
            if not allowed(u):
                continue
            try:
                head_or_probe(u)
                new = dict(spec)
                new["url"] = u
                return new, u
            except Transient:
                continue
            except Exception:
                continue
        return None, ""
    return None, ""


def cmd_pick(name: str) -> int:
    spec = load()["vendors"][name]
    last = None
    for url in spec.get("json_urls") or []:
        try:
            blob, _ = fetch(url)
            ver, rpm, sha = pick_rpm_from_json(blob)
            sys.stdout.write(f"{ver}\n{rpm}\n{sha}\n")
            return 0
        except Exception as exc:
            last = exc
    print(f"FAIL pick {name}: {last}", file=sys.stderr)
    return 1


def cmd_list() -> int:
    for name, spec in load()["vendors"].items():
        title = spec.get("title") or name
        kind = spec.get("kind") or ""
        sys.stdout.write(f"{name}\t{kind}\t{title}\n")
    return 0


def cmd_spec(name: str) -> int:
    spec = load()["vendors"].get(name)
    if not spec:
        print(f"unknown vendor {name}", file=sys.stderr)
        return 1
    json.dump(spec, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


def cmd_url(name: str) -> int:
    spec = load()["vendors"][name]
    u = spec.get("url") or (spec.get("json_urls") or [""])[0]
    sys.stdout.write(u + "\n")
    return 0 if u else 1


def cmd_heal(probe_rpm: bool) -> int:
    path = _repo_manifest()
    data = load()
    dirty = False
    still = 0
    transient = 0
    for name, spec in list(data.get("vendors", {}).items()):
        try:
            print(check_one(name, spec, probe_rpm))
            continue
        except Transient as exc:
            print(f"heal {name}: transient ({exc}) — not rewriting", file=sys.stderr)
            transient += 1
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
            print(f"FAIL {name}: no legit allowlisted replacement", file=sys.stderr)
    if dirty:
        path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        print(f"wrote {path}")
    if still:
        print(
            f"{still} vendor(s) still broken. Flathub / gpgcheck=0 / no checksum needs a human.",
            file=sys.stderr,
        )
        return 1
    if transient:
        print(f"{transient} vendor(s) had a temporary error; list unchanged", file=sys.stderr)
        return 1
    print("all vendor contracts ok")
    return 0


def cmd_check(probe_rpm: bool) -> int:
    vendors = load()["vendors"]
    failed = 0
    transient = 0
    for name, spec in vendors.items():
        try:
            print(check_one(name, spec, probe_rpm))
        except Transient as exc:
            print(f"TRANSIENT {name}: {exc}", file=sys.stderr)
            transient += 1
        except Exception as exc:
            print(f"FAIL {name}: {exc}", file=sys.stderr)
            failed += 1
    if failed:
        print(
            f"{failed} vendor contract(s) broken. Run: vendor.py heal --probe-rpm",
            file=sys.stderr,
        )
        return 1
    if transient:
        print(f"{transient} temporary error(s); not a contract break", file=sys.stderr)
        return 1
    print("all vendor contracts ok")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(
            "usage: vendor.py schema|check|heal [--probe-rpm] | list | spec NAME | pick NAME | url NAME",
            file=sys.stderr,
        )
        return 2
    cmd = argv[1]
    probe = "--probe-rpm" in argv
    if cmd == "schema":
        return cmd_schema()
    if cmd == "check":
        return cmd_check(probe)
    if cmd == "heal":
        return cmd_heal(probe)
    if cmd == "list":
        return cmd_list()
    if cmd == "spec" and len(argv) >= 3:
        return cmd_spec(argv[2])
    if cmd == "pick" and len(argv) >= 3:
        return cmd_pick(argv[2])
    if cmd == "url" and len(argv) >= 3:
        return cmd_url(argv[2])
    print(
        "usage: vendor.py schema|check|heal [--probe-rpm] | list | spec NAME | pick NAME | url NAME",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
