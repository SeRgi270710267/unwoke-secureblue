#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated. UNWOKE-SHIPPED-FIRST. Stock #2354 was a request.
# Network filesystem *clients* (NFS/CIFS) off until ujust set-network-fs on.
# Stock already masks nfs-server; they still allow mounting shares. We do not.
set -euo pipefail

ALLOW="/etc/unwoke/allow-network-fs"
MOD_SRC="/usr/share/unwoke/modprobe-network-fs.conf"
MOD_DST="/etc/modprobe.d/unwoke-network-fs.conf"
# Stock already masks the NFS *server*. Never unmask those, even when clients are on.
SERVER_UNITS=(nfs-server.service nfs-mountd.service)
CLIENT_UNITS=(nfs-client.target rpc-statd.service)

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    command -v run0 >/dev/null || { echo "need run0 (wheel user)" >&2; exit 1; }
    run0 "$@"
  fi
}

wanted_lock() { [[ ! -f "${ALLOW}" ]]; }

cmd_apply_boot() {
  [[ "$(id -u)" -eq 0 ]] || exit 1
  mkdir -p /etc/modprobe.d
  local u
  for u in "${SERVER_UNITS[@]}"; do
    systemctl disable --now "$u" >/dev/null 2>&1 || true
    systemctl mask "$u" >/dev/null 2>&1 || true
  done
  if wanted_lock; then
    [[ -f "${MOD_SRC}" ]] && cp -a "${MOD_SRC}" "${MOD_DST}"
    for u in "${CLIENT_UNITS[@]}"; do
      systemctl disable --now "$u" >/dev/null 2>&1 || true
      systemctl mask "$u" >/dev/null 2>&1 || true
    done
  else
    rm -f "${MOD_DST}"
    for u in "${CLIENT_UNITS[@]}"; do
      systemctl unmask "$u" >/dev/null 2>&1 || true
    done
  fi
}

cmd_on() {
  as_root mkdir -p /etc/unwoke
  as_root touch "${ALLOW}"
  as_root /usr/bin/bash /usr/libexec/unwoke/network-fs.sh apply-boot
  echo "NFS/CIFS client modules ALLOWED. You may need: run0 modprobe cifs   (or nfs)"
  echo "Revert: ujust set-network-fs off"
}

cmd_off() {
  as_root rm -f "${ALLOW}"
  as_root /usr/bin/bash /usr/libexec/unwoke/network-fs.sh apply-boot
  echo "NFS/CIFS LOCKED (modules blacklisted; nfs-server stays masked)."
  echo "Already-mounted shares stay until unmount. Revert: ujust set-network-fs on"
}

cmd_status() {
  if wanted_lock; then
    echo "off/locked (default — ${ALLOW} absent)"
  else
    echo "on/allowed (${ALLOW})"
  fi
}

case "${1:-status}" in
  on|enable|allow) cmd_on ;;
  off|disable|lock) cmd_off ;;
  apply-boot) cmd_apply_boot ;;
  status) cmd_status ;;
  *)
    echo "usage: ujust set-network-fs on|off|status" >&2
    exit 2
    ;;
esac
