#!/usr/bin/env python3
"""At compose: write /usr/share/unwoke/ca-blocklist/*.pem for Fedora CAs not in Mozilla website set."""
from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path

MOZ = Path("/usr/share/unwoke/mozilla-ca-sha256.txt")
BUNDLE_CANDIDATES = (
    Path("/etc/pki/tls/certs/ca-bundle.crt"),
    Path("/usr/share/pki/ca-trust-source/ca-bundle.trust.p11-kit"),
    Path("/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem"),
)
OUT = Path("/usr/share/unwoke/ca-blocklist")


def mozilla() -> set[str]:
    out: set[str] = set()
    if not MOZ.is_file():
        print("ca-trim-build: missing mozilla-ca-sha256.txt", file=sys.stderr)
        return out
    for line in MOZ.read_text(encoding="utf-8").splitlines():
        line = line.strip().lower()
        if not line or line.startswith("#"):
            continue
        out.add(line.replace(":", "").replace(" ", ""))
    return out


def pems_from_bundle(path: Path) -> list[bytes]:
    text = path.read_text(encoding="utf-8", errors="replace")
    return [
        m.group(0).encode("ascii", errors="replace")
        for m in re.finditer(
            r"-----BEGIN CERTIFICATE-----\r?\n.*?\r?\n-----END CERTIFICATE-----",
            text,
            re.S,
        )
    ]


def main() -> int:
    moz = mozilla()
    if not moz:
        print("ca-trim-build: empty Mozilla list; skip", file=sys.stderr)
        return 0
    pems: list[bytes] = []
    for p in BUNDLE_CANDIDATES:
        if p.is_file() and "BEGIN CERTIFICATE" in p.read_text(encoding="utf-8", errors="replace"):
            pems = pems_from_bundle(p)
            if pems:
                print(f"ca-trim-build: {len(pems)} certs from {p}")
                break
    if not pems:
        print("ca-trim-build: no PEM bundle in image; skip", file=sys.stderr)
        return 0
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*.pem"):
        old.unlink()
    n = 0
    for pem in pems:
        inner = re.sub(br"-----[^-]+-----", b"", pem)
        inner = re.sub(br"\s+", b"", inner)
        try:
            import base64

            der = base64.b64decode(inner)
        except Exception:
            continue
        fp = hashlib.sha256(der).hexdigest()
        if fp in moz:
            continue
        n += 1
        (OUT / f"{fp[:16]}.pem").write_bytes(pem + b"\n")
    print(f"ca-trim-build: blocked {n} extra CAs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
