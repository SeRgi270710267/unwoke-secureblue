#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# After Origin extra dnf, Packages can be malformed. Restore the
# pre-flavor sqlite+WAL saved by apply-unwoke.sh (drop live sidecars
# first so Origin WAL cannot attach), then drop the backup so it never
# ships. WAL checkpoint only — do not rpm --rebuilddb (empties the
# index). Do not bump titanoboa.
set -oue pipefail

bak=/usr/share/unwoke/.rpmdb-pre-flavor.sqlite

flavor=""
[[ -f /usr/share/unwoke/flavor ]] && flavor="$(tr -d '[:space:]' < /usr/share/unwoke/flavor)"

# Origin extra dnf (Brave RPM + selinux-policy-devel) malforms Packages.
# apply-unwoke now checkpoints before save, so bak is a complete sqlite.
# Drop live Origin WAL first, copy sqlite only. Do not reattach a WAL.
# Brave files stay on disk. Do not bump titanoboa.
place_rpmdb() {
  local dest="$1"
  [[ -d "${dest}" ]] || return 0
  rm -f "${dest}/rpmdb.sqlite-wal" "${dest}/rpmdb.sqlite-shm"
  cp -a "${bak}" "${dest}/rpmdb.sqlite"
  echo "unwoke: Origin — restored pre-flavor rpmdb into ${dest} ($(stat -c %s "${dest}/rpmdb.sqlite" 2>/dev/null || echo ?) bytes)"
}

if [[ "${flavor}" == "brave-origin" && -f "${bak}" ]]; then
  echo "unwoke: Origin — restoring pre-flavor rpmdb (drop Origin WAL first)"
  for dest in /usr/lib/sysimage/rpm /usr/share/rpm /var/lib/rpm; do
    place_rpmdb "${dest}"
  done
fi

rm -f "${bak}" "${bak}-wal" "${bak}-shm"

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
