#!/usr/bin/env bash
# Live ISO only: stock blacklists squashfs, which the LiveCD root needs.
# SPDX-FileCopyrightText: Copyright 2026 The Secureblue Authors
# SPDX-License-Identifier: Apache-2.0
# Origin overlay dnf can ship a malformed RPM sqlite. Titanoboa then dies
# on `dnf install -y dracut-live` with updates-released-f$releasever 404.
# This hook runs in a writable podman rootfs *before* that dnf.
# Do not bump titanoboa.

set -euo pipefail

ldconfig
sed -i '/^install squashfs /d' /usr/lib/modprobe.d/secureblue.conf
echo 'install squashfs /sbin/modprobe --ignore-install squashfs' > /etc/modprobe.d/zz-squashfs-override.conf
echo 'install_items+=" /usr/lib64/libno_rlimit_as.so /etc/ld.so.cache /etc/modprobe.d/zz-squashfs-override.conf "' > /etc/dracut.conf.d/libs.conf

echo "unwoke: repair RPM sqlite / dnf releasever before titanoboa dnf"
echo "unwoke: rpm _dbpath=$(rpm -E '%_dbpath' 2>/dev/null || echo empty)"
ls -li /usr/lib/sysimage/rpm /usr/share/rpm /var/lib/rpm 2>/dev/null || true

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
        con = sqlite3.connect(f"file:{db.as_posix()}?mode=rw", uri=True)
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

if command -v rpm >/dev/null; then
  rpm --rebuilddb && echo "unwoke: rpm --rebuilddb ok" || echo "WARN: rpm --rebuilddb rc=$?"
fi

# Split-brain: rpm may rebuild %_dbpath while dnf5 still opens another sqlite.
dbpath="$(rpm -E '%_dbpath' 2>/dev/null || true)"
src=""
if [[ -n "${dbpath}" && -f "${dbpath}/rpmdb.sqlite" ]]; then
  src="${dbpath}/rpmdb.sqlite"
elif [[ -f /usr/lib/sysimage/rpm/rpmdb.sqlite ]]; then
  src="/usr/lib/sysimage/rpm/rpmdb.sqlite"
fi
if [[ -n "${src}" ]]; then
  for dest in /usr/lib/sysimage/rpm /usr/share/rpm /var/lib/rpm; do
    [[ -d "${dest}" ]] || continue
    if [[ "${dest}/rpmdb.sqlite" -ef "${src}" ]]; then
      continue
    fi
    cp -a "${src}" "${dest}/rpmdb.sqlite"
    rm -f "${dest}/rpmdb.sqlite-wal" "${dest}/rpmdb.sqlite-shm"
    echo "unwoke: copied rpmdb to ${dest}"
  done
fi

fedora="$(rpm --eval '%{fedora}' 2>/dev/null || true)"
echo "unwoke: rpm fedora=${fedora:-empty}"
if [[ "${fedora}" =~ ^[0-9]+$ ]]; then
  mkdir -p /etc/dnf/vars /etc/yum/vars
  printf '%s\n' "${fedora}" > /etc/dnf/vars/releasever
  printf '%s\n' "${fedora}" > /etc/yum/vars/releasever
  echo "unwoke: wrote dnf vars releasever=${fedora}"
else
  echo "WARN: %{fedora} empty; titanoboa dnf may 404 on f\$releasever" >&2
fi

rpm -q kernel-core >/dev/null 2>&1 && echo "unwoke: rpm -q kernel-core ok" || echo "WARN: rpm -q kernel-core failed"

# Prove dnf can expand releasever *before* titanoboa's hardcoded dnf.
if [[ "${fedora}" =~ ^[0-9]+$ ]] && command -v dnf5 >/dev/null; then
  dnf5 --releasever="${fedora}" -y install dracut-live && echo "unwoke: dnf5 installed dracut-live" || echo "WARN: dnf5 install dracut-live rc=$?"
elif [[ "${fedora}" =~ ^[0-9]+$ ]] && command -v dnf >/dev/null; then
  dnf --releasever="${fedora}" -y install dracut-live && echo "unwoke: dnf installed dracut-live" || echo "WARN: dnf install dracut-live rc=$?"
fi
