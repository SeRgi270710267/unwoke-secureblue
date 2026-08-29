#!/usr/bin/env bash
# noexec,nosuid,nodev on /dev/shm and /tmp (stock #697). Default on.
# Electron/old JIT that mmap(PROT_EXEC) from shm: ujust set-ramdisk-exec on
set -euo pipefail

ALLOW="/etc/unwoke/allow-ramdisk-exec"
FSTAB="/etc/fstab"
MARK_BEGIN="# unwoke-ramdisk-begin"
MARK_END="# unwoke-ramdisk-end"
TMP_DROP_DIR="/etc/systemd/system/tmp.mount.d"
TMP_DROP="${TMP_DROP_DIR}/90-unwoke-noexec.conf"

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    command -v run0 >/dev/null || { echo "need run0 (wheel user)" >&2; exit 1; }
    run0 "$@"
  fi
}

wanted_lock() { [[ ! -f "${ALLOW}" ]]; }

strip_fstab() {
  [[ -f "${FSTAB}" ]] || return 0
  local tmp
  tmp="$(mktemp)"
  awk -v b="${MARK_BEGIN}" -v e="${MARK_END}" '
    $0==b {skip=1; next}
    $0==e {skip=0; next}
    !skip {print}
  ' "${FSTAB}" > "${tmp}"
  mv "${tmp}" "${FSTAB}"
}

cmd_apply_boot() {
  [[ "$(id -u)" -eq 0 ]] || exit 1
  strip_fstab
  rm -f "${TMP_DROP}"
  rmdir "${TMP_DROP_DIR}" 2>/dev/null || true
  if wanted_lock; then
    mkdir -p "${TMP_DROP_DIR}"
    cat > "${TMP_DROP}" <<'EOF'
[Mount]
Options=mode=1777,strictatime,nosuid,nodev,noexec,size=50%,nr_inodes=1m
EOF
    {
      echo "${MARK_BEGIN}"
      echo "tmpfs /dev/shm tmpfs defaults,nodev,nosuid,noexec 0 0"
      echo "${MARK_END}"
    } >> "${FSTAB}"
    mount -o remount,nodev,nosuid,noexec /dev/shm 2>/dev/null || true
    systemctl daemon-reload >/dev/null 2>&1 || true
    mount -o remount,nosuid,nodev,noexec /tmp 2>/dev/null || true
  else
    mount -o remount,exec /dev/shm 2>/dev/null || true
    systemctl daemon-reload >/dev/null 2>&1 || true
  fi
}

cmd_on() {
  as_root mkdir -p /etc/unwoke
  as_root rm -f "${ALLOW}"
  as_root /usr/bin/bash /usr/libexec/unwoke/ramdisk.sh apply-boot
  echo "RAM disk LOCKED (noexec on /dev/shm and /tmp). Revert: ujust set-ramdisk-exec on"
}

cmd_off() {
  as_root mkdir -p /etc/unwoke
  as_root touch "${ALLOW}"
  as_root /usr/bin/bash /usr/libexec/unwoke/ramdisk.sh apply-boot
  echo "RAM disk exec ALLOWED. Put the lock back: ujust set-ramdisk-exec off"
}

cmd_status() {
  if wanted_lock; then
    echo "off/locked (default — noexec /dev/shm /tmp)"
  else
    echo "on/allowed (${ALLOW})"
  fi
}

case "${1:-status}" in
  on|enable|allow) cmd_off ;;
  off|disable|lock) cmd_on ;;
  apply-boot) cmd_apply_boot ;;
  status) cmd_status ;;
  *)
    echo "usage: ujust set-ramdisk-exec on|off|status" >&2
    exit 2
    ;;
esac
