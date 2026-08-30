#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Checkpoint RPM sqlite WAL after overlay dnf, then drop WAL/SHM.
# Titanoboa ISO wrap runs `dnf install -y dracut-live` in this rootfs.
# Origin wraps 26-29: malformed Packages db, $releasever never expanded.
# rpm --rebuilddb fails in ostree compose (do not run it — bake 89 rc=1).
# Do not PRAGMA integrity_check: RPM sqlite is not a vanilla db (Origin
# bake died on "*** in database main ***" while dnf still works on Trivalent).
# Last step must not reopen sqlite (that recreates -shm; inspect used to fail).
# Do not bump titanoboa.
set -oue pipefail

echo "unwoke: checkpoint RPM sqlite WAL so the ISO wrap can dnf"

python3 - <<'PY'
import sqlite3
import sys
from pathlib import Path

dirs = [Path("/usr/lib/sysimage/rpm"), Path("/usr/share/rpm"), Path("/var/lib/rpm")]
seen = []
for d in dirs:
    if not d.is_dir():
        continue
    for db in sorted(d.glob("*.sqlite")):
        try:
            real = db.resolve()
        except OSError:
            real = db
        if real in seen:
            continue
        seen.append(real)
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
if not seen:
    print("WARN: no *.sqlite under RPM dirs")
PY

for dir in /usr/lib/sysimage/rpm /usr/share/rpm /var/lib/rpm; do
  [[ -d "${dir}" ]] || continue
  find "${dir}" -maxdepth 1 \( \
    -name '*.sqlite-wal' -o -name '*.sqlite-shm' -o -name '__db.*' \
  \) -delete 2>/dev/null || true
done

echo "unwoke: RPM sqlite WAL checkpointed; sidecars dropped"
