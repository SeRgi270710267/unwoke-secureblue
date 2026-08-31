#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Anonymity-adjacent host net that does not cut SELinux/Safe Browsing/NTS.
# Default: TCP timestamps off (clock-skew leak). Optional: hostname "host".
# Not Tor. Not Tails. Real IP hide = ujust install-whonix.
set -euo pipefail

ALLOW_TS="/etc/unwoke/allow-tcp-timestamps"
WANT_HOST="/etc/unwoke/anon-hostname"
PREV_HOST="/etc/unwoke/anon-hostname.prev"
SRC="/usr/share/unwoke/sysctl-anon.conf"
DST="/etc/sysctl.d/99-unwoke-anon.conf"

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    command -v run0 >/dev/null || { echo "need run0 (wheel user)" >&2; exit 1; }
    run0 "$@"
  fi
}

ts_off() { [[ ! -f "${ALLOW_TS}" ]]; }
host_on() { [[ -f "${WANT_HOST}" ]]; }

apply_boot() {
  [[ "$(id -u)" -eq 0 ]] || exit 1
  mkdir -p /etc/unwoke /etc/sysctl.d
  if ts_off && [[ -f "${SRC}" ]]; then
    cp -a "${SRC}" "${DST}"
  else
    rm -f "${DST}"
  fi
  sysctl --system >/dev/null 2>&1 || sysctl -p "${DST}" >/dev/null 2>&1 || true
  if host_on; then
    if [[ ! -f "${PREV_HOST}" ]]; then
      hostnamectl hostname 2>/dev/null > "${PREV_HOST}" || hostname > "${PREV_HOST}" || true
    fi
    hostnamectl hostname host >/dev/null 2>&1 || hostname host || true
  elif [[ -f "${PREV_HOST}" ]]; then
    local old
    old="$(tr -d '[:space:]' < "${PREV_HOST}")"
    [[ -n "${old}" ]] && hostnamectl hostname "${old}" >/dev/null 2>&1 || true
    rm -f "${PREV_HOST}"
  fi
}

usage() {
  echo "usage: anon-net.sh timestamps|hostname|apply-boot|status  [on|off|status]" >&2
  exit 2
}

cmd_status() {
  if ts_off; then echo "tcp-timestamps: off (default — less clock-skew leak)"; else echo "tcp-timestamps: on (${ALLOW_TS})"; fi
  if host_on; then echo "hostname: host (${WANT_HOST})"; else echo "hostname: unchanged (DHCP still does not send it)"; fi
}

case "${1:-status}" in
  apply-boot) apply_boot ;;
  status) cmd_status ;;
  timestamps|anon-net)
    shift || true
    case "${1:-status}" in
      on|enable|stock)
        as_root mkdir -p /etc/unwoke
        as_root touch "${ALLOW_TS}"
        as_root /usr/bin/bash /usr/libexec/unwoke/anon-net.sh apply-boot
        echo "TCP timestamps ON (stock). Clock-skew leak back. Revert: ujust set-anon-net off"
        ;;
      off|disable|lock)
        as_root rm -f "${ALLOW_TS}"
        as_root /usr/bin/bash /usr/libexec/unwoke/anon-net.sh apply-boot
        echo "TCP timestamps OFF (default). Revert: ujust set-anon-net on"
        ;;
      status) ts_off && echo "off (default)" || echo "on" ;;
      *) usage ;;
    esac
    ;;
  hostname)
    shift || true
    case "${1:-status}" in
      on|enable|host)
        as_root mkdir -p /etc/unwoke
        as_root touch "${WANT_HOST}"
        as_root /usr/bin/bash /usr/libexec/unwoke/anon-net.sh apply-boot
        echo "Local hostname set to host. DHCP still silent either way. Revert: ujust set-anon-hostname off"
        ;;
      off|disable)
        as_root rm -f "${WANT_HOST}"
        as_root /usr/bin/bash /usr/libexec/unwoke/anon-net.sh apply-boot
        echo "Local hostname restored. Revert: ujust set-anon-hostname on"
        ;;
      status) host_on && echo "host" || echo "unchanged" ;;
      *) usage ;;
    esac
    ;;
  *) usage ;;
esac
