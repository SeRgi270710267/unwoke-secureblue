#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# After Origin extra dnf, Packages can be malformed. Restore the
# pre-flavor sqlite saved by apply-unwoke.sh, then drop the backup so
# it never ships. WAL checkpoint only — do not rpm --rebuilddb (empties
# the index). Do not bump titanoboa.
set -oue pipefail

bak=/usr/share/unwoke/.rpmdb-pre-flavor.sqlite

db=""
for cand in /usr/lib/sysimage/rpm/rpmdb.sqlite /usr/share/rpm/rpmdb.sqlite /var/lib/rpm/rpmdb.sqlite; do
  [[ -f "${cand}" ]] || continue
  db="${cand}"
  break
done

flavor=""
[[ -f /usr/share/unwoke/flavor ]] && flavor="$(tr -d '[:space:]' < /usr/share/unwoke/flavor)"

# Origin extra dnf (Brave RPM + selinux-policy-devel) malforms Packages.
# Recovered stubs are ~4 MiB and make live-USB dnf install hundreds of
# packages; selinux-fix then dies on unlabeled rpc_pipefs. Always restore
# the pre-flavor db on Origin. Brave files stay on disk.
if [[ "${flavor}" == "brave-origin" && -f "${bak}" && -n "${db}" ]]; then
  echo "unwoke: Origin — restoring pre-flavor rpmdb over ${db}"
  cp -a "${bak}" "${db}"
  for dest in /usr/lib/sysimage/rpm /usr/share/rpm /var/lib/rpm; do
    [[ -d "${dest}" ]] || continue
    if [[ -e "${dest}/rpmdb.sqlite" ]] && [[ "${dest}/rpmdb.sqlite" -ef "${db}" ]]; then
      continue
    fi
    cp -a "${db}" "${dest}/rpmdb.sqlite"
  done
fi

rm -f "${bak}"

echo "unwoke: checkpoint RPM sqlite WAL"
python3 - <<'PY'
import sqlite3
import sys
from pathlib import Path

dirs = [Path("/usr/lib/sysimage/rpm"), Path("/usr/share/rpm"), Path("/var/lib/rpm")]
seen = []
for d in dirs:
    if not d.is_dir():
        continue
    for dbp in sorted(d.glob("*.sqlite")):
        try:
            real = dbp.resolve()
        except OSError:
            real = dbp
        if real in seen:
            continue
        seen.append(real)
        try:
            con = sqlite3.connect(str(dbp))
            try:
                con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
                con.commit()
            finally:
                con.close()
            print(f"unwoke: checkpointed {dbp}")
        except sqlite3.Error as e:
            print(f"WARN: checkpoint {dbp}: {e}", file=sys.stderr)
PY

for dir in /usr/lib/sysimage/rpm /usr/share/rpm /var/lib/rpm; do
  [[ -d "${dir}" ]] || continue
  find "${dir}" -maxdepth 1 \( \
    -name '*.sqlite-wal' -o -name '*.sqlite-shm' -o -name '__db.*' \
  \) -delete 2>/dev/null || true
done

echo "unwoke: RPM sqlite ready for titanoboa dnf"
