#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Checkpoint and rebuild the RPM sqlite db after overlay dnf.
# Titanoboa's ISO wrap runs `dnf install -y dracut-live` inside this rootfs.
# Origin wraps 26-29 died: "database disk image is malformed" then
# $releasever never expanded. Do not bump titanoboa. Repair the db we ship.
set -oue pipefail

RPMDIRS=(/usr/lib/sysimage/rpm /usr/share/rpm /var/lib/rpm)

checkpoint_sqlite() {
  python3 - <<'PY'
import sqlite3
from pathlib import Path
dirs = ["/usr/lib/sysimage/rpm", "/usr/share/rpm", "/var/lib/rpm"]
for d in dirs:
    p = Path(d)
    if not p.is_dir():
        continue
    for db in p.glob("*.sqlite"):
        try:
            con = sqlite3.connect(str(db))
            try:
                con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
                con.commit()
            finally:
                con.close()
        except sqlite3.Error as e:
            print(f"WARN: checkpoint {db}: {e}")
PY
}

drop_sidecars() {
  local dir
  for dir in "${RPMDIRS[@]}"; do
    [[ -d "${dir}" ]] || continue
    find "${dir}" -maxdepth 1 \( \
      -name '*.sqlite-wal' -o -name '*.sqlite-shm' -o -name '__db.*' \
    \) -delete 2>/dev/null || true
  done
}

checkpoint_sqlite
if command -v rpm >/dev/null; then
  rpm --rebuilddb
elif command -v rpmdb >/dev/null; then
  rpmdb --rebuilddb
else
  echo "FAIL: rpm not in PATH; cannot rebuild rpmdb" >&2
  exit 1
fi
checkpoint_sqlite
drop_sidecars

if ! rpm -q rpm >/dev/null 2>&1; then
  echo "FAIL: rpm -q still broken after rebuilddb" >&2
  rpm -q rpm || true
  exit 1
fi

python3 - <<'PY'
import sqlite3
import sys
from pathlib import Path

cands = []
for rel in ("/usr/lib/sysimage/rpm", "/usr/share/rpm", "/var/lib/rpm"):
    d = Path(rel)
    if d.is_dir():
        cands.extend(sorted(d.glob("*.sqlite")))
    p = d / "rpmdb.sqlite"
    if p.is_file() and p not in cands:
        cands.append(p)
seen = []
for db in cands:
    if not db.is_file():
        continue
    real = db.resolve()
    if real in seen:
        continue
    seen.append(real)
    for side in (Path(str(db) + "-wal"), Path(str(db) + "-shm")):
        if side.is_file() and side.stat().st_size > 0:
            print(f"FAIL: leftover {side}", file=sys.stderr)
            raise SystemExit(1)
    try:
        con = sqlite3.connect(f"file:{db.as_posix()}?mode=ro", uri=True)
        try:
            row = con.execute("PRAGMA integrity_check").fetchone()
        finally:
            con.close()
    except sqlite3.Error as e:
        print(f"FAIL: cannot open {db}: {e}", file=sys.stderr)
        raise SystemExit(1)
    chk = row[0] if row else "empty"
    if chk != "ok":
        print(f"FAIL: {db} integrity: {chk}", file=sys.stderr)
        raise SystemExit(1)
    print(f"unwoke: rpmdb ok {db}")
if not seen:
    print("FAIL: no rpmdb.sqlite after rebuilddb", file=sys.stderr)
    raise SystemExit(1)
PY

echo "unwoke: rpmdb rebuilt; rpm -q rpm ok"
