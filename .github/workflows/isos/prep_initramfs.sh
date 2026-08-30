#!/usr/bin/env bash
# Live ISO only: stock blacklists squashfs, which the LiveCD root needs.
# SPDX-FileCopyrightText: Copyright 2026 The Secureblue Authors
# SPDX-License-Identifier: Apache-2.0
# Origin overlay dnf can ship a malformed RPM sqlite. Titanoboa then dies
# on `dnf install -y dracut-live` ($releasever never expands). This hook
# runs in a writable podman rootfs *before* that dnf. Do not bump titanoboa.

set -euo pipefail

ldconfig
sed -i '/^install squashfs /d' /usr/lib/modprobe.d/secureblue.conf
echo 'install squashfs /sbin/modprobe --ignore-install squashfs' > /etc/modprobe.d/zz-squashfs-override.conf
echo 'install_items+=" /usr/lib64/libno_rlimit_as.so /etc/ld.so.cache /etc/modprobe.d/zz-squashfs-override.conf "' > /etc/dracut.conf.d/libs.conf

echo "unwoke: repair RPM sqlite before titanoboa dnf"
python3 - <<'PY'
import os
import sqlite3
import sys
from pathlib import Path

def dbs():
    seen = []
    for d in (Path("/usr/lib/sysimage/rpm"), Path("/usr/share/rpm"), Path("/var/lib/rpm")):
        p = d / "rpmdb.sqlite"
        if not p.is_file():
            continue
        try:
            real = p.resolve()
        except OSError:
            real = p
        if real in seen:
            continue
        seen.append(real)
        yield p

ok = 0
for db in dbs():
    try:
        con = sqlite3.connect(str(db))
        try:
            con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
            con.commit()
            dst = Path("/tmp") / f"{db.name}.vacuum"
            if dst.exists():
                dst.unlink()
            con.execute("VACUUM INTO ?", (str(dst),))
        finally:
            con.close()
        os.replace(dst, db)
        for side in (Path(str(db) + "-wal"), Path(str(db) + "-shm")):
            try:
                side.unlink()
            except FileNotFoundError:
                pass
        print(f"unwoke: vacuumed {db}")
        ok += 1
    except sqlite3.Error as e:
        print(f"WARN: vacuum {db}: {e}", file=sys.stderr)
if ok == 0:
    print("WARN: no RPM sqlite vacuumed", file=sys.stderr)
PY

# Writable live rootfs — ostree compose rejected rebuilddb.
if command -v rpm >/dev/null; then
  rpm --rebuilddb && echo "unwoke: rpm --rebuilddb ok" || echo "WARN: rpm --rebuilddb rc=$?"
fi

fedora="$(rpm --eval '%{fedora}' 2>/dev/null || true)"
echo "unwoke: rpm fedora=${fedora:-empty}"
if [[ ! "${fedora}" =~ ^[0-9]+$ ]]; then
  echo "WARN: %{fedora} still empty; titanoboa dnf may fail" >&2
fi
