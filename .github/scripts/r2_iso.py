#!/usr/bin/env python3
"""Upload one signed ISO to a private R2 bucket, or record monthly ops.

Free R2 is 10 GB-month, 1M Class A ops, and 10M Class B ops. This stops
at 9 GB and at 800k / 8M ops. It prints counts and byte totals only.

A live ISO is about 4.8 GB. Twelve flavors do not fit. R2 stores one
stick, unwoke-silverblue-trivalent, at most 5.5 GB. The 9 GB bucket cap
stays. Other ISO jobs skip and their old objects are deleted.

    python3 .github/scripts/r2_iso.py --selftest
    python3 .github/scripts/r2_iso.py upload
    python3 .github/scripts/r2_iso.py ops
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

# Decimal GB, matching Cloudflare's 10 GB-month line. Never store more than this.
STORAGE_CAP = 9_000_000_000
# One object. 5.5 GB. Silverblue Trivalent is about 4.8 GB. Kinoite is about 5.3 GB.
OBJECT_CAP = 5_500_000_000
# Free plan is 1_000_000 Class A and 10_000_000 Class B. Stop before either.
OPS_A_CAP = 800_000
OPS_B_CAP = 8_000_000
# Explicit allowlist. Env R2_ISO_IMAGES may name a subset, never a wider set.
R2_ISO_IMAGES = ("unwoke-silverblue-trivalent",)
ENDPOINT_PREFIX = "https://"
ENDPOINT_SUFFIX = ".r2.cloudflarestorage.com"

OPS_QUERY = """
query R2Ops($account: String!, $start: Time!, $end: Time!) {
  viewer {
    accounts(filter: { accountTag: $account }) {
      r2OperationsAdaptiveGroups(
        limit: 10000
        filter: { datetime_geq: $start, datetime_leq: $end }
      ) {
        sum { requests }
        dimensions { actionType }
      }
    }
  }
}
"""


class R2Error(Exception):
    pass


def allowlist() -> tuple[str, ...]:
    raw = os.environ.get("R2_ISO_IMAGES", "").strip()
    if not raw:
        return R2_ISO_IMAGES
    asked = tuple(part.strip() for part in raw.split(",") if part.strip())
    if not asked or any(name not in R2_ISO_IMAGES for name in asked):
        raise R2Error("R2_ISO_IMAGES is wider than the code allowlist")
    return asked


def plan_upload(
    objects: list[tuple[str, int]],
    flavor: str,
    new_files: dict[str, int],
    cap: int = STORAGE_CAP,
    flavors: tuple[str, ...] = R2_ISO_IMAGES,
    object_cap: int = OBJECT_CAP,
) -> dict:
    """Decide upload or skip. delete is empty unless the upload fits.

    objects are (key, size) already in the bucket. new_files maps the
    destination key to the new size. Keys outside the allowlist are not
    counted. They are deleted when this upload fits, or when the job is
    for an image that is not allowlisted.
    """
    outside = [key for key, _size in objects if key.split("/", 1)[0] not in flavors]
    if flavor not in flavors:
        return {"action": "skip", "reason": "not-served", "delete": outside, "projected": None}
    new_total = sum(new_files.values())
    new_keys = set(new_files)
    remaining = 0
    delete: list[str] = list(outside)
    for key, size in objects:
        top = key.split("/", 1)[0]
        if top not in flavors:
            continue
        if top == flavor and key not in new_keys:
            delete.append(key)
            continue
        if key in new_keys:
            continue
        remaining += size
    projected = remaining + new_total
    if new_total > object_cap or projected > cap:
        return {
            "action": "skip",
            "reason": "over-object" if new_total > object_cap else "over-bucket",
            "delete": [],
            "projected": projected,
            "new_total": new_total,
            "per": object_cap,
        }
    return {
        "action": "upload",
        "reason": "ok",
        "delete": delete,
        "projected": projected,
        "new_total": new_total,
        "per": object_cap,
    }


def would_fit(objects: list[tuple[str, int]], new_files: dict[str, int], cap: int = STORAGE_CAP) -> bool:
    """Size after overwrite. Keys we are about to write are not counted twice."""
    new_keys = set(new_files)
    total = sum(size for key, size in objects if key not in new_keys)
    total += sum(new_files.values())
    return total <= cap


def classify_ops(rows: list[dict]) -> tuple[int, int]:
    """Split analytics rows into Class A and Class B. Unknown actions count as A."""
    class_a = 0
    class_b = 0
    for row in rows:
        if not isinstance(row, dict):
            continue
        summary = row.get("sum") if isinstance(row.get("sum"), dict) else {}
        try:
            count = int(summary.get("requests") or 0)
        except (TypeError, ValueError):
            continue
        dims = row.get("dimensions") if isinstance(row.get("dimensions"), dict) else {}
        action = str(dims.get("actionType") or "")
        if action.startswith("Get") or action.startswith("Head"):
            class_b += count
        else:
            class_a += count
    return class_a, class_b


def endpoint_ok(value: str) -> bool:
    if not value.startswith(ENDPOINT_PREFIX) or value.endswith("/"):
        return False
    host = value[len(ENDPOINT_PREFIX) :]
    if "/" in host or "@" in host or "?" in host:
        return False
    if not host.endswith(ENDPOINT_SUFFIX):
        return False
    account = host[: -len(ENDPOINT_SUFFIX)]
    return account.isalnum() and account == account.lower() and len(account) >= 16


def _alarm(cmd: str, extra: str) -> None:
    if not os.environ.get("GITHUB_REPOSITORY"):
        return
    script = Path(__file__).resolve().parent / "issue-alarm.sh"
    if not script.is_file():
        return
    env = os.environ.copy()
    env["ALARM_EXTRA"] = extra
    env["GH_TOKEN"] = env.get("GH_TOKEN") or env.get("GITHUB_TOKEN", "")
    subprocess.run(["bash", str(script), "r2", cmd], check=False, env=env)


def _rclone_env() -> dict[str, str]:
    endpoint = os.environ.get("R2_ENDPOINT", "")
    if not endpoint_ok(endpoint):
        raise R2Error("R2 endpoint must be https://<account>.r2.cloudflarestorage.com")
    env = os.environ.copy()
    env["RCLONE_CONFIG_R2_TYPE"] = "s3"
    env["RCLONE_CONFIG_R2_PROVIDER"] = "Cloudflare"
    env["RCLONE_CONFIG_R2_ACCESS_KEY_ID"] = os.environ.get("R2_ACCESS_KEY_ID", "")
    env["RCLONE_CONFIG_R2_SECRET_ACCESS_KEY"] = os.environ.get("R2_SECRET_ACCESS_KEY", "")
    env["RCLONE_CONFIG_R2_ENDPOINT"] = endpoint.rstrip("/")
    env["RCLONE_CONFIG_R2_ACL"] = "private"
    return env


def _rclone(args: list[str]) -> str:
    env = _rclone_env()
    proc = subprocess.run(
        ["rclone", *args],
        check=False,
        capture_output=True,
        env=env,
        text=True,
    )
    if proc.returncode != 0:
        raise R2Error(f"rclone exited {proc.returncode}")
    return proc.stdout


def _ensure_rclone() -> None:
    installer = Path(__file__).resolve().parent / "install-rclone.sh"
    subprocess.run(["bash", str(installer)], check=True)


def list_objects(bucket: str) -> list[tuple[str, int]]:
    raw = _rclone(["lsjson", f"r2:{bucket}", "--recursive"])
    data = json.loads(raw or "[]")
    found: list[tuple[str, int]] = []
    if not isinstance(data, list):
        raise R2Error("bucket list was not a list")
    for item in data:
        if not isinstance(item, dict) or item.get("IsDir"):
            continue
        key = str(item.get("Path") or "")
        if not key or key.startswith("/") or ".." in key.split("/"):
            continue
        try:
            size = int(item.get("Size") or 0)
        except (TypeError, ValueError):
            size = 0
        found.append((key, size))
    return found


def _delete_key(bucket: str, key: str) -> None:
    try:
        _rclone(["deletefile", f"r2:{bucket}/{key}"])
    except R2Error:
        still_there = any(name == key for name, _size in list_objects(bucket))
        if still_there:
            raise R2Error("delete failed")


def _bucket() -> str:
    name = os.environ.get("R2_BUCKET", "") or "unwoke-isos"
    if name != "unwoke-isos":
        raise R2Error("R2 bucket must be unwoke-isos")
    return name


def _creds_ready() -> bool:
    return bool(os.environ.get("R2_ACCESS_KEY_ID") and os.environ.get("R2_SECRET_ACCESS_KEY") and os.environ.get("R2_ENDPOINT"))


def _new_files(flavor: str) -> dict[str, int]:
    iso = Path(os.environ.get("ISO_FILE", ""))
    if not iso.is_file():
        raise R2Error("ISO file missing")
    directory = iso.parent
    sums = directory / "SHA256SUMS"
    if not sums.is_file():
        raise R2Error("SHA256SUMS missing")
    names = sums.read_text(encoding="utf-8").split()
    if "latest.iso" not in names:
        raise R2Error("SHA256SUMS does not name latest.iso")
    files = {
        f"{flavor}/latest.iso": iso.stat().st_size,
        f"{flavor}/SHA256SUMS": sums.stat().st_size,
    }
    sig = directory / "SHA256SUMS.sig"
    if sig.is_file() and sig.stat().st_size > 0:
        files[f"{flavor}/SHA256SUMS.sig"] = sig.stat().st_size
    else:
        print("r2: SHA256SUMS.sig missing; ISO and checksum still considered")
    return files


def _sources(flavor: str) -> dict[str, Path]:
    iso = Path(os.environ["ISO_FILE"])
    directory = iso.parent
    sources = {
        f"{flavor}/latest.iso": iso,
        f"{flavor}/SHA256SUMS": directory / "SHA256SUMS",
    }
    sig = directory / "SHA256SUMS.sig"
    if sig.is_file():
        sources[f"{flavor}/SHA256SUMS.sig"] = sig
    return sources


def upload() -> int:
    flavor = os.environ.get("IMAGE_NAME", "")
    if not flavor or "/" in flavor or flavor.startswith("."):
        print("r2: flavor name refused")
        return 1
    try:
        served = allowlist()
    except R2Error as exc:
        print(f"r2: {exc}")
        return 1
    if flavor not in served:
        print(f"r2: {flavor} is not in R2_ISO_IMAGES ({', '.join(served)}); upload skipped")
        if not _creds_ready():
            print("r2: skipped leftover delete, credentials unset")
            return 0
        try:
            _ensure_rclone()
            bucket = _bucket()
            outside = [key for key, _size in list_objects(bucket) if key.split("/", 1)[0] not in served]
            for key in outside:
                _delete_key(bucket, key)
            total = sum(size for _key, size in list_objects(bucket))
            print(f"r2: removed {len(outside)} objects outside the allowlist")
            print(f"r2: bucket {total} bytes")
        except (R2Error, subprocess.CalledProcessError, json.JSONDecodeError, OSError):
            print("r2: leftover delete failed; upload still skipped")
            return 0
        return 0
    if not _creds_ready():
        print("r2: skipped, credentials unset")
        return 0
    try:
        files = _new_files(flavor)
        bucket = _bucket()
    except R2Error as exc:
        print(f"r2: {exc}")
        return 1
    if not endpoint_ok(os.environ.get("R2_ENDPOINT", "")):
        print("r2: endpoint refused")
        return 1
    try:
        _ensure_rclone()
        objects = list_objects(bucket)
        decision = plan_upload(objects, flavor, files, flavors=served)
    except (R2Error, subprocess.CalledProcessError, json.JSONDecodeError, OSError):
        print("r2: list failed; upload skipped")
        _alarm("open", f"R2 list failed for {flavor}. Nothing was uploaded.")
        return 0
    projected = decision.get("projected")
    print(
        f"r2: {files[f'{flavor}/latest.iso']} bytes, "
        f"projected {projected}, cap {STORAGE_CAP}, {decision['action']}"
    )
    if decision["action"] != "upload":
        _alarm(
            "open",
            f"{flavor} was not uploaded. Reason: {decision['reason']}. "
            f"Bytes: {decision.get('new_total')}. Projected: {projected}. "
            f"Cap: {STORAGE_CAP}. Per object: {decision.get('per')}. "
            "Served stick: unwoke-silverblue-trivalent. "
            "Do not buy R2 storage.",
        )
        report_ops()
        return 0
    try:
        for key in decision["delete"]:
            _delete_key(bucket, key)
        objects = list_objects(bucket)
        if not would_fit(objects, files):
            print("r2: refused after a fresh list; nothing new uploaded")
            _alarm("open", f"{flavor} still does not fit under {STORAGE_CAP} bytes. Nothing new was uploaded.")
            report_ops()
            return 0
        for key, path in _sources(flavor).items():
            _rclone(["copyto", str(path), f"r2:{bucket}/{key}", "--s3-no-check-bucket"])
        objects = list_objects(bucket)
        total = sum(size for _key, size in objects)
        print(f"r2: bucket {total} bytes")
        if total > STORAGE_CAP:
            for key in files:
                _delete_key(bucket, key)
            print("r2: rolled back; bucket would have passed 9 GB")
            _alarm("open", f"Rolled back {flavor}. Bucket listing passed {STORAGE_CAP} bytes.")
            report_ops()
            return 0
    except (R2Error, subprocess.CalledProcessError, json.JSONDecodeError, OSError):
        print("r2: upload failed")
        _alarm("open", f"R2 upload failed for {flavor}.")
        return 0
    _alarm("close", "")
    report_ops()
    return 0


def _parse_ops(payload: dict) -> tuple[int, int] | None:
    if payload.get("errors"):
        return None
    data = payload.get("data")
    if not isinstance(data, dict):
        return None
    viewer = data.get("viewer")
    if not isinstance(viewer, dict):
        return None
    accounts = viewer.get("accounts")
    if not isinstance(accounts, list) or not accounts:
        return None
    groups = accounts[0].get("r2OperationsAdaptiveGroups") if isinstance(accounts[0], dict) else None
    if not isinstance(groups, list):
        return None
    return classify_ops(groups)


def fetch_ops(token: str, account: str) -> tuple[int, int] | None:
    now = datetime.now(timezone.utc)
    start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    body = json.dumps(
        {
            "query": OPS_QUERY,
            "variables": {
                "account": account,
                "start": start.strftime("%Y-%m-%dT%H:%M:%SZ"),
                "end": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
            },
        }
    ).encode()
    req = urllib.request.Request(
        "https://api.cloudflare.com/client/v4/graphql",
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "User-Agent": "unwoke-r2-ops",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, UnicodeError):
        return None
    if not isinstance(payload, dict):
        return None
    return _parse_ops(payload)


def report_ops() -> None:
    token = os.environ.get("CLOUDFLARE_API_TOKEN", "")
    account = os.environ.get("CLOUDFLARE_ACCOUNT_ID", "")
    if not token or not account:
        print("r2-ops=unknown")
        return
    try:
        counted = fetch_ops(token, account)
    except R2Error:
        counted = None
    if counted is None:
        print("r2-ops=unknown")
        return
    class_a, class_b = counted
    print(f"r2-ops: classA={class_a} classB={class_b} capA={OPS_A_CAP} capB={OPS_B_CAP}")
    if class_a >= OPS_A_CAP or class_b >= OPS_B_CAP:
        _alarm(
            "open",
            f"R2 ops this month: Class A {class_a} (guard {OPS_A_CAP} of 1000000), "
            f"Class B {class_b} (guard {OPS_B_CAP} of 10000000). Do not buy R2.",
        )


def selftest() -> int:
    ok = True
    cap = 9_000
    flavors = ("silver", "kinoite")
    decision = plan_upload([], "silver", {"silver/latest.iso": 4_000}, cap, flavors, 5_500)
    if decision["action"] != "upload" or decision["projected"] != 4_000:
        print("selftest FAIL empty upload")
        ok = False
    decision = plan_upload([], "silver", {"silver/latest.iso": 5_501}, cap, flavors, 5_500)
    if decision["action"] != "skip" or decision["reason"] != "over-object" or decision["delete"]:
        print("selftest FAIL over object")
        ok = False
    objects = [("kinoite/latest.iso", 4_000), ("silver/old.iso", 4_000), ("nvidia/latest.iso", 4_000)]
    decision = plan_upload(objects, "silver", {"silver/latest.iso": 4_000, "silver/SHA256SUMS": 10}, cap, flavors, 5_500)
    if decision["action"] != "upload":
        print("selftest FAIL prune and replace")
        ok = False
    if "nvidia/latest.iso" not in decision["delete"] or "silver/old.iso" not in decision["delete"]:
        print("selftest FAIL delete set")
        ok = False
    if "kinoite/latest.iso" in decision["delete"]:
        print("selftest FAIL kept the other stick")
        ok = False
    if decision["projected"] != 8_010:
        print("selftest FAIL projected")
        ok = False
    only = ("unwoke-silverblue-trivalent",)
    leftovers = [
        ("unwoke-kinoite-trivalent/latest.iso", 5_285_187_584),
        ("nvidia/latest.iso", 4_000_000_000),
    ]
    decision = plan_upload(
        leftovers,
        "unwoke-silverblue-trivalent",
        {"unwoke-silverblue-trivalent/latest.iso": 4_785_299_456},
        STORAGE_CAP,
        only,
        OBJECT_CAP,
    )
    if decision["action"] != "upload" or decision["projected"] != 4_785_299_456:
        print("selftest FAIL silverblue ignores other sticks")
        ok = False
    if "unwoke-kinoite-trivalent/latest.iso" not in decision["delete"] or "nvidia/latest.iso" not in decision["delete"]:
        print("selftest FAIL delete non-allowlist")
        ok = False
    decision = plan_upload([], "unwoke-kinoite-trivalent", {"unwoke-kinoite-trivalent/latest.iso": 100}, STORAGE_CAP, only, OBJECT_CAP)
    if decision["reason"] != "not-served":
        print("selftest FAIL kinoite skipped")
        ok = False
    crowded = [("kinoite/latest.iso", 5_000)]
    decision = plan_upload(crowded, "silver", {"silver/latest.iso": 4_500}, cap, flavors, 5_500)
    if decision["action"] != "skip" or decision["reason"] != "over-bucket":
        print("selftest FAIL over bucket")
        ok = False
    decision = plan_upload([], "nvidia", {"nvidia/latest.iso": 100}, cap, flavors, 5_500)
    if decision["reason"] != "not-served":
        print("selftest FAIL served set")
        ok = False
    if would_fit([("kinoite/latest.iso", 4_500)], {"silver/latest.iso": 4_500}, cap) is not True:
        print("selftest FAIL exact cap")
        ok = False
    if would_fit([("kinoite/latest.iso", 4_501)], {"silver/latest.iso": 4_500}, cap):
        print("selftest FAIL over exact cap")
        ok = False
    class_a, class_b = classify_ops(
        [
            {"sum": {"requests": 3}, "dimensions": {"actionType": "PutObject"}},
            {"sum": {"requests": 9}, "dimensions": {"actionType": "GetObject"}},
            {"sum": {"requests": 1}, "dimensions": {"actionType": "ListObjects"}},
        ]
    )
    if class_a != 4 or class_b != 9:
        print("selftest FAIL ops split")
        ok = False
    sample = {
        "data": {
            "viewer": {
                "accounts": [
                    {
                        "r2OperationsAdaptiveGroups": [
                            {"sum": {"requests": 2}, "dimensions": {"actionType": "HeadObject"}}
                        ]
                    }
                ]
            }
        }
    }
    parsed = _parse_ops(sample)
    if parsed != (0, 2):
        print("selftest FAIL ops parse")
        ok = False
    if _parse_ops({"errors": [{"message": "nope"}]}) is not None:
        print("selftest FAIL ops error")
        ok = False
    if not endpoint_ok("https://abc123def4567890.r2.cloudflarestorage.com"):
        print("selftest FAIL endpoint")
        ok = False
    if endpoint_ok("https://user:pass@abc123def4567890.r2.cloudflarestorage.com"):
        print("selftest FAIL endpoint userinfo")
        ok = False
    if endpoint_ok("http://abc123def4567890.r2.cloudflarestorage.com"):
        print("selftest FAIL endpoint scheme")
        ok = False
    if R2_ISO_IMAGES != ("unwoke-silverblue-trivalent",):
        print("selftest FAIL allowlist")
        ok = False
    if OBJECT_CAP != 5_500_000_000 or STORAGE_CAP != 9_000_000_000:
        print("selftest FAIL caps")
        ok = False
    if OPS_A_CAP != 800_000 or OPS_B_CAP != 8_000_000:
        print("selftest FAIL ops caps")
        ok = False
    previous = os.environ.get("R2_ISO_IMAGES")
    os.environ["R2_ISO_IMAGES"] = "unwoke-kinoite-trivalent"
    try:
        allowlist()
        print("selftest FAIL env widened the allowlist")
        ok = False
    except R2Error:
        pass
    if previous is None:
        os.environ.pop("R2_ISO_IMAGES", None)
    else:
        os.environ["R2_ISO_IMAGES"] = previous
    print("r2 iso selftest " + ("ok" if ok else "FAILED"))
    return 0 if ok else 1


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        return selftest()
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "upload":
        return upload()
    if cmd == "ops":
        report_ops()
        return 0
    print("usage: r2_iso.py upload|ops|--selftest", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
