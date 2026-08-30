#!/usr/bin/env bash
# Live ISO only: stock blacklists squashfs, which the LiveCD root needs.
# SPDX-FileCopyrightText: Copyright 2026 The Secureblue Authors
# SPDX-License-Identifier: Apache-2.0
# Origin overlay can ship a malformed RPM sqlite. Titanoboa then dies
# on `dnf install -y dracut-live` and `rpm -q kernel-core`.
# Do **not** rpm --rebuilddb (empties the index). Do **not** sqlite3
# .recover a ~90 MiB db (4.3 MiB stub). If rpm -q kernel-core fails,
# throw the sqlite away, initdb, justdb kernel-core + dracut-live.
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

echo "WARN: rpm -q kernel-core failed on live rootfs — replacing malformed rpmdb" >&2
ls -d /usr/lib/modules/* 2>/dev/null || true

fedora="$(rpm --eval '%{fedora}' 2>/dev/null || true)"
echo "unwoke: rpm fedora=${fedora:-empty}"
if [[ "${fedora}" =~ ^[0-9]+$ ]]; then
  mkdir -p /etc/dnf/vars /etc/yum/vars
  printf '%s\n' "${fedora}" > /etc/dnf/vars/releasever
  printf '%s\n' "${fedora}" > /etc/yum/vars/releasever
  echo "unwoke: wrote dnf vars releasever=${fedora}"
fi

# ISO wraps through 33311501669: justdb into the 95 MiB ostree sqlite
# dies (`Name` table malformed). sqlite3 .recover smashes it to 4.3 MiB
# and titanoboa dnf installs 177 packages. Throw the db away, initdb,
# justdb kernel-core + dracut-live. titanoboa's `dnf install dracut-live`
# then sees it already installed. Do not bump titanoboa.
krel="$(ls -1 /usr/lib/modules 2>/dev/null | head -n 1 || true)"
[[ -n "${krel}" && "${fedora}" =~ ^[0-9]+$ ]] || {
  echo "FAIL: no kernel modules dir or fedora releasever" >&2
  exit 1
}

for dir in /usr/lib/sysimage/rpm /usr/share/rpm /var/lib/rpm; do
  [[ -d "${dir}" ]] || continue
  rm -f "${dir}"/rpmdb.sqlite "${dir}"/rpmdb.sqlite-wal "${dir}"/rpmdb.sqlite-shm \
        "${dir}"/__db.* 2>/dev/null || true
done
mkdir -p /usr/share/rpm /usr/lib/sysimage/rpm
rpm --initdb
echo "unwoke: rpm --initdb at $(rpm -E '%_dbpath')"

mkdir -p /tmp/unwoke-kernel-rpm
(
  cd /tmp/unwoke-kernel-rpm
  rm -f ./*.rpm
  if command -v dnf5 >/dev/null; then
    dnf5 --releasever="${fedora}" -y --nogpgcheck download \
      "kernel-core-${krel}" dracut-live \
      || dnf5 --releasever="${fedora}" -y --nogpgcheck download kernel-core dracut-live
  else
    dnf --releasever="${fedora}" -y --nogpgcheck download \
      "kernel-core-${krel}" dracut-live \
      || dnf --releasever="${fedora}" -y --nogpgcheck download kernel-core dracut-live
  fi
  ls -l ./*.rpm
  rpm --justdb --nodeps -ivh ./*.rpm
)
dbpath="$(rpm -E '%_dbpath')"
if [[ -n "${dbpath}" && -f "${dbpath}/rpmdb.sqlite" ]]; then
  for dest in /usr/lib/sysimage/rpm /usr/share/rpm /var/lib/rpm; do
    [[ -d "${dest}" ]] || continue
    if [[ "${dest}/rpmdb.sqlite" -ef "${dbpath}/rpmdb.sqlite" ]]; then
      continue
    fi
    cp -a "${dbpath}/rpmdb.sqlite" "${dest}/rpmdb.sqlite"
    rm -f "${dest}/rpmdb.sqlite-wal" "${dest}/rpmdb.sqlite-shm"
  done
fi

if rpm -q kernel-core >/dev/null 2>&1; then
  echo "unwoke: rpm -q kernel-core ok ($(rpm -q kernel-core --queryformat '%{evr}.%{arch}\n'))"
else
  echo "FAIL: rpm -q kernel-core still failed after initdb+justdb" >&2
  rpm -qa || true
  exit 1
fi
if rpm -q dracut-live >/dev/null 2>&1; then
  echo "unwoke: rpm -q dracut-live ok ($(rpm -q dracut-live))"
else
  echo "WARN: dracut-live not in justdb; titanoboa dnf may still pull deps" >&2
fi
# Files stay the ostree image. Only the live USB RPM index is a stub of
# kernel-core + dracut-live so titanoboa queryformat + dnf install no-op.
