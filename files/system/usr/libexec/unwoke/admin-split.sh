#!/usr/bin/env bash
# Wheel keeps TTY/run0. Graphical login blocked for wheel once a non-wheel
# daily user exists. First boot prompts on tty1 before GDM/SDDM (skips if off).
# ujust set-admin-split on|off|add NAME|status
set -euo pipefail

OFF="/etc/unwoke/admin-split.off"
DONE="/etc/unwoke/admin-split.done"
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
  local uid shell user groups
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
  local f tmp
  for f in "${PAM_TARGETS[@]}"; do
    [[ -f "$f" && ! -L "$f" ]] || continue
    grep -q "^${BEGIN}$" "$f" && continue
    tmp="$(mktemp)"
    printf '%s\n' "${SNIP}" > "$tmp"
    cat "$f" >> "$tmp"
    cat "$tmp" > "$f"
    rm -f "$tmp"
  done
}

create_daily() {
  local name="$1" pass="$2"
  [[ "${name}" =~ ^[a-z_][a-z0-9_-]*$ ]] || return 1
  [[ "${name}" != root && "${name}" != wheel ]] || return 1
  if ! getent passwd "${name}" >/dev/null; then
    useradd -m -U -s /bin/bash "${name}"
  fi
  gpasswd -d "${name}" wheel >/dev/null 2>&1 || true
  echo "${name}:${pass}" | chpasswd
}

cmd_apply_boot() {
  [[ "$(id -u)" -eq 0 ]] || exit 1
  mkdir -p /etc/unwoke
  if wanted && has_daily_user; then
    inject_pam
    touch "${DONE}"
  else
    strip_pam
  fi
}

cmd_add_stdin() {
  local name="${1:-}" pass=""
  [[ "${name}" =~ ^[a-z_][a-z0-9_-]*$ ]] || { echo "invalid username" >&2; exit 2; }
  IFS= read -r pass || true
  [[ -n "${pass}" ]] || { echo "empty password" >&2; exit 2; }
  mkdir -p /etc/unwoke
  if ! create_daily "${name}" "${pass}"; then
    echo "Could not create ${name}" >&2
    exit 1
  fi
  rm -f "${OFF}"
  inject_pam
  touch "${DONE}"
  echo "Daily user ${name}. Log in as ${name} on the greeter. Admin: Ctrl+Alt+F3 + run0."
}

cmd_setup_prompt() {
  [[ "$(id -u)" -eq 0 ]] || exit 0
  mkdir -p /etc/unwoke
  if ! wanted; then
    exit 0
  fi
  if has_daily_user; then
    inject_pam
    touch "${DONE}"
    exit 0
  fi
  export TERM="${TERM:-linux}"
  export NCURSES_NO_UTF8_ACS=1
  local name="" pass="" pass2=""
  if command -v dialog >/dev/null && [[ -t 0 ]]; then
    dialog --backtitle "Unwoke SecureBlue" --title "This is not frozen" --msgbox \
      "Create a daily (non-wheel) user before the greeter.\n\nThis screen is supposed to be here. GNOME/KDE starts after you finish or skip.\n\nWheel stays for Ctrl+Alt+F3 and run0.\nSkip: Cancel, or leave the username empty (5 minute timeout also skips)." \
      16 60 || true
    name="$(dialog --stdout --inputbox "Daily username (lowercase)" 8 40 || true)"
    name="$(printf '%s' "${name}" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
    if [[ -n "${name}" ]]; then
      pass="$(dialog --stdout --insecure --passwordbox "Password for ${name}" 8 40 || true)"
      pass2="$(dialog --stdout --insecure --passwordbox "Password again" 8 40 || true)"
    fi
  else
    echo
    echo "=============================================="
    echo "  Unwoke SecureBlue — this is not frozen"
    echo "=============================================="
    echo "Create a daily (non-wheel) user before the greeter."
    echo "GNOME/KDE starts after this. Wheel stays for TTY/run0."
    echo "Skip: wait 5 minutes or leave username empty."
    echo
    printf "Daily username: "
    read -r name || true
    name="$(printf '%s' "${name}" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
    if [[ -n "${name}" ]]; then
      printf "Password: "
      stty -echo 2>/dev/null || true
      read -r pass || true
      stty echo 2>/dev/null || true
      echo
      printf "Password again: "
      stty -echo 2>/dev/null || true
      read -r pass2 || true
      stty echo 2>/dev/null || true
      echo
    fi
  fi
  if [[ -z "${name}" ]]; then
    echo "Skipped. Later: Unwoke setup → Daily user, or ujust set-admin-split add NAME"
    exit 0
  fi
  if [[ -z "${pass}" || "${pass}" != "${pass2}" ]]; then
    echo "Passwords empty or mismatch. Skipped. ujust set-admin-split add ${name}"
    exit 0
  fi
  if ! create_daily "${name}" "${pass}"; then
    echo "Could not create ${name}. Skipped."
    exit 0
  fi
  inject_pam
  touch "${DONE}"
  echo "Created ${name}. Log in as ${name} on the greeter. Admin: Ctrl+Alt+F3 + run0."
}

cmd_on() {
  as_root mkdir -p /etc/unwoke
  as_root rm -f "${OFF}"
  as_root /usr/bin/bash /usr/libexec/unwoke/admin-split.sh apply-boot
  if has_daily_user; then
    echo "Admin split ON. Wheel cannot open GDM/SDDM."
  else
    echo "No daily user yet. Reboot for the tty1 prompt, or: ujust set-admin-split add NAME"
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
  echo "Set a password for ${name}:"
  if getent passwd "${name}" >/dev/null; then
    as_root gpasswd -d "${name}" wheel >/dev/null 2>&1 || true
    as_root passwd "${name}"
  else
    as_root useradd -m -U -s /bin/bash "${name}"
    as_root gpasswd -d "${name}" wheel >/dev/null 2>&1 || true
    as_root passwd "${name}"
  fi
  as_root mkdir -p /etc/unwoke
  as_root rm -f "${OFF}"
  as_root touch "${DONE}"
  as_root /usr/bin/bash /usr/libexec/unwoke/admin-split.sh apply-boot
  echo "Daily user ${name}. Log in as ${name} on the greeter."
}

cmd_status() {
  if ! wanted; then
    echo "off (${OFF})"
    return
  fi
  if has_daily_user; then
    echo "on (wheel GUI blocked; daily user present)"
  else
    echo "pending (tty1 prompt at boot, or ujust set-admin-split add NAME)"
  fi
}

case "${1:-status}" in
  on|enable) cmd_on ;;
  off|disable) cmd_off ;;
  add) cmd_add "${2:-}" ;;
  add-stdin)
    [[ "$(id -u)" -eq 0 ]] || { echo "add-stdin needs root/run0" >&2; exit 1; }
    cmd_add_stdin "${2:-}"
    ;;
  apply-boot) cmd_apply_boot ;;
  setup-prompt) cmd_setup_prompt ;;
  status) cmd_status ;;
  *)
    echo "usage: ujust set-admin-split on|off|add NAME|status" >&2
    exit 2
    ;;
esac
