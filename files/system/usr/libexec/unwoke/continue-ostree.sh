#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated. UNWOKE-SHIPPED-FIRST.
# Resume a wizard after rpm-ostree layer + reboot. User config only.
# Source this file. Do not exec.
: "${XDG_CONFIG_HOME:=$HOME/.config}"
UNWOKE_CONTINUE="${XDG_CONFIG_HOME}/unwoke/continue"

unwoke_write_continue() {
  mkdir -p "${XDG_CONFIG_HOME}/unwoke"
  : > "${UNWOKE_CONTINUE}"
  local a
  for a in "$@"; do
    printf '%s\n' "$a" >> "${UNWOKE_CONTINUE}"
  done
  rm -f "${XDG_CONFIG_HOME}/unwoke/continue-whonix"
}

unwoke_clear_continue() {
  rm -f "${UNWOKE_CONTINUE}" "${XDG_CONFIG_HOME}/unwoke/continue-whonix"
}
