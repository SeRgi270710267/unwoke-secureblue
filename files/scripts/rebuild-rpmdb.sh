#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Make the RPM sqlite self-contained after overlay dnf.
# Titanoboa ISO wrap runs `dnf install -y dracut-live` in this rootfs.
# Origin wraps 26-29: malformed Packages db, $releasever never expanded.
# rpm-ostree compose already leaves `rpm -q` unusable — do not require it.
# Do not bump titanoboa.
set -oue pipefail

echo "unwoke: checkpoint RPM sqlite (WAL) so the ISO wrap can dnf"

python3 - <<'PY'
import sqlite3
import sys
from pathlib import Path

dirs = [Path("/usr/lib/sysimage/rpm"), Path("/usr/share/rpm"), Path("/var/lib/rpm")]
n = 0
for d in dirs:
    if not d.is_dir():
        continue
    for db in sorted(d.glob("*.sqlite")):
        n += 1
        try:
            con = sqlite3.connect(str(db))
            try:
                con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
                con.commit()
            finally:
                con.close()
            print(f"unwoke: checkpointed {db}")
        except sqlite3.Error as e:
            print(f"WARN: checkpoint {db}: {e}", file=sys.stderr)
if n == 0:
    print("WARN: no *.sqlite under RPM dirs yet")
PY

# Best-effort. rpm-ostree compose often rejects rebuilddb; sqlite checkpoint
# is the repair that actually ships. Do not fail the bake on this.
if command -v rpm >/dev/null; then
  echo "unwoke: rpm --rebuilddb (best-effort)"
  rpm --rebuilddb && echo "unwoke: rpm --rebuilddb ok" || echo "WARN: rpm --rebuilddb rc=$?"
elif command -v rpmdb >/dev/null; then
  echo "unwoke: rpmdb --rebuilddb (best-effort)"
  rpmdb --rebuilddb && echo "unwoke: rpmdb --rebuilddb ok" || echo "WARN: rpmdb --rebuilddb rc=$?"
else
  echo "WARN: rpm not in PATH"
fi

python3 - <<'PY'
import sqlite3
import sys
from pathlib import Path

dirs = [Path("/usr/lib/sysimage/rpm"), Path("/usr/share/rpm"), Path("/var/lib/rpm")]
for d in dirs:
    if not d.is_dir():
        continue
    for db in sorted(d.glob("*.sqlite")):
        try:
            con = sqlite3.connect(str(db))
            try:
                con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
                con.commit()
            finally:
                con.close()
        except sqlite3.Error as e:
            print(f"WARN: re-checkpoint {db}: {e}", file=sys.stderr)
PY

for dir in /usr/lib/sysimage/rpm /usr/share/rpm /var/lib/rpm; do
  [[ -d "${dir}" ]] || continue
  find "${dir}" -maxdepth 1 \( \
    -name '*.sqlite-wal' -o -name '*.sqlite-shm' -o -name '__db.*' \
  \) -delete 2>/dev/null || true
done

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
    print(f"unwoke: rpmdb sqlite ok {db}")
if not seen:
    print("FAIL: no rpmdb.sqlite after overlay dnf", file=sys.stderr)
    raise SystemExit(1)
PY

echo "unwoke: RPM sqlite checkpointed; ISO wrap dnf should see a readable db"
