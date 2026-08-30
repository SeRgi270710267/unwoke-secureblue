#!/usr/bin/env bash
# Live ISO only: stock blacklists squashfs, which the LiveCD root needs.
# SPDX-FileCopyrightText: Copyright 2026 The Secureblue Authors
# SPDX-License-Identifier: Apache-2.0
# Origin overlay dnf can ship a malformed RPM sqlite. Titanoboa then dies
# on `dnf install -y dracut-live` and `rpm -q kernel-core`.
# Do **not** rpm --rebuilddb here: bake ISO wrap c3e61d0 emptied the index
# (kernel-core "is not installed" while the modules dir is on disk).
# sqlite3 .recover the existing db, write dnf releasever, then dnf.
# Do not bump titanoboa.

set -euo pipefail

ldconfig
sed -i '/^install squashfs /d' /usr/lib/modprobe.d/secureblue.conf
echo 'install squashfs /sbin/modprobe --ignore-install squashfs' > /etc/modprobe.d/zz-squashfs-override.conf
echo 'install_items+=" /usr/lib64/libno_rlimit_as.so /etc/ld.so.cache /etc/modprobe.d/zz-squashfs-override.conf "' > /etc/dracut.conf.d/libs.conf

echo "unwoke: recover RPM sqlite before titanoboa dnf"
echo "unwoke: rpm _dbpath=$(rpm -E '%_dbpath' 2>/dev/null || echo empty)"

db=""
for cand in "$(rpm -E '%_dbpath' 2>/dev/null)/rpmdb.sqlite" \
            /usr/share/rpm/rpmdb.sqlite \
            /usr/lib/sysimage/rpm/rpmdb.sqlite \
            /var/lib/rpm/rpmdb.sqlite; do
  [[ -f "${cand}" ]] || continue
  db="${cand}"
  break
done

if [[ -z "${db}" ]]; then
  echo "WARN: no rpmdb.sqlite found" >&2
elif ! command -v sqlite3 >/dev/null; then
  echo "WARN: sqlite3 CLI missing; cannot recover ${db}" >&2
else
  recovered="/tmp/rpmdb.recovered.sqlite"
  rm -f "${recovered}"
  echo "unwoke: sqlite3 .recover ${db}"
  if sqlite3 "${db}" ".recover" | sqlite3 "${recovered}" \
     && [[ -s "${recovered}" ]]; then
    cp -a "${recovered}" "${db}"
    rm -f "${db}-wal" "${db}-shm"
    echo "unwoke: recovered ${db} ($(stat -c %s "${db}" 2>/dev/null || echo ?) bytes)"
    src="${db}"
    for dest in /usr/lib/sysimage/rpm /usr/share/rpm /var/lib/rpm; do
      [[ -d "${dest}" ]] || continue
      if [[ -e "${dest}/rpmdb.sqlite" ]] && [[ "${dest}/rpmdb.sqlite" -ef "${src}" ]]; then
        continue
      fi
      cp -a "${src}" "${dest}/rpmdb.sqlite"
      rm -f "${dest}/rpmdb.sqlite-wal" "${dest}/rpmdb.sqlite-shm"
      echo "unwoke: copied recovered rpmdb to ${dest}"
    done
  else
    echo "WARN: sqlite3 .recover failed for ${db}" >&2
  fi
fi

fedora="$(rpm --eval '%{fedora}' 2>/dev/null || true)"
echo "unwoke: rpm fedora=${fedora:-empty}"
if [[ "${fedora}" =~ ^[0-9]+$ ]]; then
  mkdir -p /etc/dnf/vars /etc/yum/vars
  printf '%s\n' "${fedora}" > /etc/dnf/vars/releasever
  printf '%s\n' "${fedora}" > /etc/yum/vars/releasever
  echo "unwoke: wrote dnf vars releasever=${fedora}"
fi

if rpm -q kernel-core >/dev/null 2>&1; then
  echo "unwoke: rpm -q kernel-core ok ($(rpm -q kernel-core))"
else
  echo "WARN: rpm -q kernel-core still failed" >&2
  ls -d /usr/lib/modules/* 2>/dev/null || true
fi

if [[ "${fedora}" =~ ^[0-9]+$ ]] && command -v dnf5 >/dev/null; then
  dnf5 --releasever="${fedora}" -y install dracut-live && echo "unwoke: dnf5 installed dracut-live" || echo "WARN: dnf5 install dracut-live rc=$?"
elif [[ "${fedora}" =~ ^[0-9]+$ ]] && command -v dnf >/dev/null; then
  dnf --releasever="${fedora}" -y install dracut-live && echo "unwoke: dnf installed dracut-live" || echo "WARN: dnf install dracut-live rc=$?"
fi
