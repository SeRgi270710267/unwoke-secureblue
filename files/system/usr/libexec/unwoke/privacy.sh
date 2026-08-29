#!/usr/bin/env bash
# Phone-home extras stock still does. Default: countme/connectivity/DHCP hostname off,
# thumbnails off. Revert with ujust. apply-boot every boot so a stock update cannot
# unmask countme. Does not touch SELinux, USBGuard, fwupd, or Safe Browsing.
set -euo pipefail

ALLOW_COUNTME="/etc/unwoke/allow-countme"
ALLOW_CONN="/etc/unwoke/allow-connectivity"
ALLOW_DHCP="/etc/unwoke/allow-dhcp-hostname"
ALLOW_THUMBS="/etc/unwoke/allow-thumbnails"
NM_DIR="/etc/NetworkManager/conf.d"
NM_CONN="${NM_DIR}/90-unwoke-connectivity.conf"
NM_DHCP="${NM_DIR}/90-unwoke-dhcp.conf"
SRC_CONN="/usr/share/unwoke/nm-privacy-connectivity.conf"
SRC_DHCP="/usr/share/unwoke/nm-privacy-dhcp.conf"
DCONF_SNIP="/etc/dconf/db/local.d/00-unwoke-thumbnails"
SRC_DCONF="/usr/share/unwoke/dconf-thumbnails-off"
DOLPHIN_ETC="/etc/xdg/dolphinrc"
SRC_DOLPHIN="/usr/share/unwoke/dolphin-thumbnails-off"
SRC_GNOME="/usr/share/unwoke/dconf-gnome-privacy"
DCONF_GNOME="/etc/dconf/db/local.d/01-unwoke-gnome-privacy"
SRC_RESOLVED="/usr/share/unwoke/resolved-privacy.conf"
RESOLVED_DST="/etc/systemd/resolved.conf.d/90-unwoke-privacy.conf"
COUNTME_UNITS=(rpm-ostree-countme.timer rpm-ostree-countme.service)

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    command -v run0 >/dev/null || { echo "need run0 (wheel user)" >&2; exit 1; }
    run0 "$@"
  fi
}

countme_off() { [[ ! -f "${ALLOW_COUNTME}" ]]; }
conn_off() { [[ ! -f "${ALLOW_CONN}" ]]; }
dhcp_off() { [[ ! -f "${ALLOW_DHCP}" ]]; }
thumbs_off() { [[ ! -f "${ALLOW_THUMBS}" ]]; }

apply_countme() {
  local u
  if countme_off; then
    for u in "${COUNTME_UNITS[@]}"; do
      systemctl disable --now "$u" >/dev/null 2>&1 || true
      systemctl mask "$u" >/dev/null 2>&1 || true
    done
  else
    for u in "${COUNTME_UNITS[@]}"; do
      systemctl unmask "$u" >/dev/null 2>&1 || true
    done
    systemctl enable --now rpm-ostree-countme.timer >/dev/null 2>&1 || true
  fi
}

apply_nm_file() {
  local src="$1" dst="$2" want_off="$3"
  mkdir -p "${NM_DIR}"
  if [[ "${want_off}" == "1" && -f "${src}" ]]; then
    cp -a "${src}" "${dst}"
  else
    rm -f "${dst}"
  fi
}

apply_connections() {
  command -v nmcli >/dev/null || return 0
  systemctl is-active --quiet NetworkManager 2>/dev/null || return 0
  local uuid
  while IFS= read -r uuid; do
    [[ -n "${uuid}" ]] || continue
    if dhcp_off; then
      nmcli connection modify "${uuid}" \
        ipv4.dhcp-send-hostname no \
        ipv6.dhcp-send-hostname no \
        ipv6.addr-gen-mode stable-privacy \
        ipv6.ip6-privacy 2 \
        connection.llmnr no \
        connection.mdns no \
        >/dev/null 2>&1 || true
    else
      nmcli connection modify "${uuid}" \
        ipv4.dhcp-send-hostname yes \
        ipv6.dhcp-send-hostname yes \
        >/dev/null 2>&1 || true
    fi
  done < <(nmcli -t -f UUID connection show 2>/dev/null || true)
  nmcli general reload >/dev/null 2>&1 || true
}

apply_thumbnails() {
  mkdir -p /etc/dconf/db/local.d /etc/xdg
  if thumbs_off; then
    [[ -f "${SRC_DCONF}" ]] && cp -a "${SRC_DCONF}" "${DCONF_SNIP}"
    [[ -f "${SRC_DOLPHIN}" ]] && cp -a "${SRC_DOLPHIN}" "${DOLPHIN_ETC}"
  else
    rm -f "${DCONF_SNIP}"
    if [[ -f "${DOLPHIN_ETC}" ]] && grep -q 'unwoke-thumbnails' "${DOLPHIN_ETC}" 2>/dev/null; then
      rm -f "${DOLPHIN_ETC}"
    fi
  fi
  command -v dconf >/dev/null && dconf update >/dev/null 2>&1 || true
}

apply_gnome_privacy() {
  mkdir -p /etc/dconf/db/local.d
  if [[ -f "${SRC_GNOME}" ]]; then
    cp -a "${SRC_GNOME}" "${DCONF_GNOME}"
  fi
  command -v dconf >/dev/null && dconf update >/dev/null 2>&1 || true
}

apply_resolved() {
  mkdir -p /etc/systemd/resolved.conf.d
  if [[ -f "${SRC_RESOLVED}" ]]; then
    cp -a "${SRC_RESOLVED}" "${RESOLVED_DST}"
    if [[ -f /etc/unwoke/allow-extra-daemons ]]; then
      printf '[Resolve]\nLLMNR=no\nMulticastDNS=yes\n' > "${RESOLVED_DST}"
    fi
  else
    rm -f "${RESOLVED_DST}"
  fi
  systemctl try-reload-or-restart systemd-resolved >/dev/null 2>&1 || true
}

cmd_apply_boot() {
  [[ "$(id -u)" -eq 0 ]] || exit 1
  mkdir -p /etc/unwoke
  apply_countme
  apply_nm_file "${SRC_CONN}" "${NM_CONN}" "$(conn_off && echo 1 || echo 0)"
  apply_nm_file "${SRC_DHCP}" "${NM_DHCP}" "$(dhcp_off && echo 1 || echo 0)"
  apply_connections
  apply_thumbnails
  apply_gnome_privacy
  apply_resolved
}

set_flag() {
  local file="$1" on="$2"
  as_root mkdir -p /etc/unwoke
  if [[ "${on}" == "1" ]]; then
    as_root touch "${file}"
  else
    as_root rm -f "${file}"
  fi
  as_root /usr/bin/bash /usr/libexec/unwoke/privacy.sh apply-boot
}

cmd_status_all() {
  if countme_off; then echo "countme: off (default — Fedora countme masked)"; else echo "countme: on (${ALLOW_COUNTME})"; fi
  if conn_off; then echo "connectivity-check: off (default)"; else echo "connectivity-check: on (${ALLOW_CONN})"; fi
  if dhcp_off; then echo "dhcp-hostname: off (default — not sent)"; else echo "dhcp-hostname: on (${ALLOW_DHCP})"; fi
  if thumbs_off; then echo "thumbnails: off (default)"; else echo "thumbnails: on (${ALLOW_THUMBS})"; fi
}

usage() {
  echo "usage: privacy.sh countme|connectivity|dhcp-hostname|thumbnails|apply-boot|status  [on|off|status]" >&2
  exit 2
}

main="${1:-status}"
shift || true
case "${main}" in
  apply-boot) cmd_apply_boot ;;
  status) cmd_status_all ;;
  countme)
    case "${1:-status}" in
      on|enable) set_flag "${ALLOW_COUNTME}" 1; echo "Fedora countme ON. Revert: ujust set-countme off" ;;
      off|disable) set_flag "${ALLOW_COUNTME}" 0; echo "Fedora countme OFF (masked). Revert: ujust set-countme on" ;;
      status) countme_off && echo "off (default)" || echo "on" ;;
      *) usage ;;
    esac
    ;;
  connectivity|connectivity-check)
    case "${1:-status}" in
      on|enable) set_flag "${ALLOW_CONN}" 1; echo "Connectivity check ON (captive portals). Revert: ujust set-connectivity-check off" ;;
      off|disable) set_flag "${ALLOW_CONN}" 0; echo "Connectivity check OFF. Captive-portal pages may not pop. Revert: ujust set-connectivity-check on" ;;
      status) conn_off && echo "off (default)" || echo "on" ;;
      *) usage ;;
    esac
    ;;
  dhcp-hostname|dhcp)
    case "${1:-status}" in
      on|enable) set_flag "${ALLOW_DHCP}" 1; echo "DHCP hostname ON. Revert: ujust set-dhcp-hostname off" ;;
      off|disable) set_flag "${ALLOW_DHCP}" 0; echo "DHCP hostname OFF (RFC 7844-ish + IPv6 stable-privacy). Revert: ujust set-dhcp-hostname on" ;;
      status) dhcp_off && echo "off (default)" || echo "on" ;;
      *) usage ;;
    esac
    ;;
  thumbnails)
    case "${1:-status}" in
      on|enable) set_flag "${ALLOW_THUMBS}" 1; echo "Thumbnails ON. Revert: ujust set-thumbnails off" ;;
      off|disable) set_flag "${ALLOW_THUMBS}" 0; echo "Thumbnails OFF (GNOME Files + Dolphin). Revert: ujust set-thumbnails on" ;;
      status) thumbs_off && echo "off (default)" || echo "on" ;;
      *) usage ;;
    esac
    ;;
  *) usage ;;
esac
