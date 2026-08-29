#!/usr/bin/env bash
# Wheel users keep TTY/run0. Graphical login (GDM/SDDM) is blocked for wheel
# once a non-wheel daily user exists — so we do not brick a single-user ISO.
# ujust set-admin-split on|off|add NAME|status
set -euo pipefail

OFF="/etc/unwoke/admin-split.off"
BEGIN="# unwoke-admin-split-begin"
END="# unwoke-admin-split-end"
SNIP=$'# unwoke-admin-split-begin\nauth [success=1 default=ignore] pam_succeed_if.so quiet user notingroup wheel\nauth requisite pam_deny.so\n# unwoke-admin-split-end\n'
PAM_TARGETS=(/etc/pam.d/gdm-password /etc/pam.d/gdm-fingerprint /etc/pam.d/sddm /etc/pam.d/sddm-autologin)

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    command -v run0 >/dev/null || { echo "need run0 (wheel user)" >&2; exit 1; }
    run0 "$@"
  fi
}

wanted() { [[ ! -f "${OFF}" ]]; }

has_daily_user() {
  local line uid shell user groups
  while IFS=: read -r user _ uid _ _ _ shell; do
    [[ "${uid}" -ge 1000 && "${uid}" -lt 65534 ]] || continue
    [[ "${shell}" == *nologin* || "${shell}" == *false* || "${shell}" == *sync* ]] && continue
    groups="$(id -nG "${user}" 2>/dev/null || true)"
    if [[ " ${groups} " != *" wheel "* ]]; then
      return 0
    fi
  done < /etc/passwd
  return 1
}

strip_pam() {
  local f
  for f in "${PAM_TARGETS[@]}"; do
    [[ -f "$f" && ! -L "$f" ]] || continue
    if grep -q "^${BEGIN}$" "$f"; then
      sed -i "/^${BEGIN}$/,/^${END}$/d" "$f"
    fi
  done
}

inject_pam() {
  local f
  for f in "${PAM_TARGETS[@]}"; do
    [[ -e "$f" ]] || continue
    if [[ -L "$f" ]]; then
      continue
    fi
    [[ -f "$f" ]] || continue
    grep -q "^${BEGIN}$" "$f" && continue
    local tmp
    tmp="$(mktemp)"
    printf '%s\n' "${SNIP}" > "$tmp"
    cat "$f" >> "$tmp"
    cat "$tmp" > "$f"
    rm -f "$tmp"
  done
}

cmd_apply_boot() {
  [[ "$(id -u)" -eq 0 ]] || exit 1
  mkdir -p /etc/unwoke
  if wanted && has_daily_user; then
    inject_pam
  else
    strip_pam
  fi
}

cmd_on() {
  as_root mkdir -p /etc/unwoke
  as_root rm -f "${OFF}"
  as_root /usr/bin/bash /usr/libexec/unwoke/admin-split.sh apply-boot
  if has_daily_user; then
    echo "Admin split ON. Wheel cannot open GDM/SDDM. TTY and run0 still work."
  else
    echo "Admin split WANTED, but every human account is in wheel — GUI lock not applied (would brick login)."
    echo "Create a daily user: ujust set-admin-split add NAME"
  fi
  echo "Revert: ujust set-admin-split off"
}

cmd_off() {
  as_root mkdir -p /etc/unwoke
  as_root touch "${OFF}"
  as_root /usr/bin/bash /usr/libexec/unwoke/admin-split.sh apply-boot
  echo "Admin split OFF. Wheel can use the graphical login again."
}

cmd_add() {
  local name="${1:-}"
  [[ -n "${name}" ]] || { echo "usage: ujust set-admin-split add NAME" >&2; exit 2; }
  [[ "${name}" =~ ^[a-z_][a-z0-9_-]*$ ]] || { echo "invalid username" >&2; exit 2; }
  if getent passwd "${name}" >/dev/null; then
    echo "user ${name} already exists"
  else
    as_root useradd -m -U -s /bin/bash "${name}"
    echo "Set a password for ${name}:"
    as_root passwd "${name}"
  fi
  as_root gpasswd -d "${name}" wheel >/dev/null 2>&1 || true
  as_root mkdir -p /etc/unwoke
  as_root rm -f "${OFF}"
  as_root /usr/bin/bash /usr/libexec/unwoke/admin-split.sh apply-boot
  echo "Daily user ${name} (not in wheel). Graphical login as wheel is now blocked if PAM files allowed it."
  echo "Log in as ${name} on the greeter. Admin work: TTY or run0 from that session if policy allows."
}

cmd_status() {
  if ! wanted; then
    echo "off (${OFF})"
    return
  fi
  if has_daily_user; then
    echo "on (wheel GUI blocked; daily user present)"
  else
    echo "pending (wanted, but only wheel users exist — GUI not locked. ujust set-admin-split add NAME)"
  fi
}

case "${1:-status}" in
  on|enable) cmd_on ;;
  off|disable) cmd_off ;;
  add) cmd_add "${2:-}" ;;
  apply-boot) cmd_apply_boot ;;
  status) cmd_status ;;
  *)
    echo "usage: ujust set-admin-split on|off|add NAME|status" >&2
    exit 2
    ;;
esac
