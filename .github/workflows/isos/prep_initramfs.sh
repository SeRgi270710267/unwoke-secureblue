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

echo "unwoke: RPM sqlite / kernel-core check before titanoboa dnf"
dbpath="$(rpm -E '%_dbpath' 2>/dev/null || true)"
echo "unwoke: rpm _dbpath=${dbpath:-empty}"
ls -l /usr/lib/sysimage/rpm/rpmdb.sqlite /usr/share/rpm/rpmdb.sqlite /var/lib/rpm/rpmdb.sqlite 2>/dev/null || true

# Compose restores the full index at /usr/lib/sysimage/rpm. Live rpm
# %_dbpath is /usr/share/rpm. If those are different files, copy the
# larger sqlite onto %_dbpath before any recover.
sysimg=/usr/lib/sysimage/rpm/rpmdb.sqlite
if [[ -n "${dbpath}" && -f "${sysimg}" && -d "${dbpath}" ]]; then
  dest="${dbpath}/rpmdb.sqlite"
  if [[ -f "${dest}" ]] && [[ "${sysimg}" -ef "${dest}" ]]; then
    echo "unwoke: sysimage and %_dbpath are the same rpmdb"
  else
    syssz="$(stat -c %s "${sysimg}" 2>/dev/null || echo 0)"
    destsz="$(stat -c %s "${dest}" 2>/dev/null || echo 0)"
    echo "unwoke: rpmdb sizes sysimage=${syssz} dbpath=${destsz}"
    if [[ "${syssz}" -gt "${destsz}" ]]; then
      cp -a "${sysimg}" "${dest}"
      rm -f "${dest}-wal" "${dest}-shm"
      echo "unwoke: copied larger sysimage rpmdb onto %_dbpath"
    fi
  fi
fi

# A healthy ostree index must not be sqlite3 .recover'd — recover of Origin
# produced a 4.3 MiB stub and dnf then installed 100+ packages.
if rpm -q kernel-core >/dev/null 2>&1; then
  echo "unwoke: rpm -q kernel-core already ok ($(rpm -q kernel-core --queryformat '%{evr}.%{arch}\n'))"
  fedora="$(rpm --eval '%{fedora}' 2>/dev/null || true)"
  if [[ "${fedora}" =~ ^[0-9]+$ ]]; then
    mkdir -p /etc/dnf/vars /etc/yum/vars
    printf '%s\n' "${fedora}" > /etc/dnf/vars/releasever
    printf '%s\n' "${fedora}" > /etc/yum/vars/releasever
  fi
  exit 0
fi

echo "WARN: rpm -q kernel-core failed on live rootfs" >&2

db=""
for cand in "$(rpm -E '%_dbpath' 2>/dev/null)/rpmdb.sqlite" \
            /usr/share/rpm/rpmdb.sqlite \
            /usr/lib/sysimage/rpm/rpmdb.sqlite \
            /var/lib/rpm/rpmdb.sqlite; do
  [[ -f "${cand}" ]] || continue
  db="${cand}"
  break
done

dbsz=0
[[ -n "${db}" && -f "${db}" ]] && dbsz="$(stat -c %s "${db}")"
echo "unwoke: rpmdb ${db:-none} bytes=${dbsz}"

# A full ostree index is ~90 MiB. sqlite3 .recover of Origin's 95 MiB
# file wrote a 4.3 MiB stub and titanoboa dnf installed 189 packages.
# Never recover a large db. justdb kernel-core onto it instead.
if [[ -n "${db}" && "${dbsz}" -lt 20000000 ]]; then
  if ! command -v sqlite3 >/dev/null; then
    echo "WARN: sqlite3 CLI missing; cannot recover ${db}" >&2
  else
    recovered="/tmp/rpmdb.recovered.sqlite"
    rm -f "${recovered}"
    echo "unwoke: sqlite3 .recover ${db} (small/stub index)"
    if sqlite3 "${db}" ".recover" | sqlite3 "${recovered}" \
       && [[ -s "${recovered}" ]]; then
      cp -a "${recovered}" "${db}"
      rm -f "${db}-wal" "${db}-shm"
      echo "unwoke: recovered ${db} ($(stat -c %s "${db}" 2>/dev/null || echo ?) bytes)"
    else
      echo "WARN: sqlite3 .recover failed for ${db}" >&2
    fi
  fi
else
  echo "unwoke: skipping recover on large rpmdb (${dbsz} bytes)"
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
  echo "WARN: rpm -q kernel-core still failed after recover" >&2
  ls -d /usr/lib/modules/* 2>/dev/null || true
  # Recovered sqlite can drop ostree-shipped rows. titanoboa does
  # `rpm -q kernel-core --queryformat '%{evr}.%{arch}'`. Register the
  # on-disk kernel in the live db only (--justdb). Do not replace files.
  krel="$(ls -1 /usr/lib/modules 2>/dev/null | head -n 1 || true)"
  if [[ -n "${krel}" && "${fedora}" =~ ^[0-9]+$ ]]; then
    mkdir -p /tmp/unwoke-kernel-rpm
    (
      cd /tmp/unwoke-kernel-rpm
      if command -v dnf5 >/dev/null; then
        dnf5 --releasever="${fedora}" -y download "kernel-core-${krel}" || dnf5 --releasever="${fedora}" -y download kernel-core
      else
        dnf --releasever="${fedora}" -y download "kernel-core-${krel}" || dnf --releasever="${fedora}" -y download kernel-core
      fi
      rpm --justdb --nodeps -ivh kernel-core-*.rpm
    ) && echo "unwoke: justdb registered kernel-core for ${krel}" || echo "WARN: justdb kernel-core failed" >&2
  fi
fi

if rpm -q kernel-core >/dev/null 2>&1; then
  echo "unwoke: rpm -q kernel-core ok ($(rpm -q kernel-core --queryformat '%{evr}.%{arch}\n'))"
else
  echo "WARN: rpm -q kernel-core still failed" >&2
fi
# Do not dnf install dracut-live here. A stub recovered index made dnf
# pull 100+ packages, then rootfs-selinux-fix died on unlabeled rpc_pipefs.
# titanoboa's own `dnf install -y dracut-live` is enough once Packages
# and kernel-core are readable.
