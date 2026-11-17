#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# SPDX-License-Identifier: LicenseRef-Unwoke-SA-1.0. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Store a read:packages credential for rpm-ostree and bootc.
# The token is read from the terminal, never from argv, and never echoed.
set -euo pipefail
umask 077

AUTH_PY="${UNWOKE_INVITE_AUTH_PY:-/usr/libexec/unwoke/invite_auth.py}"

usage() {
  echo "usage: invite-login.sh [--status|--require|login|logout]" >&2
  exit 2
}

if [[ ! -f "${AUTH_PY}" ]]; then
  echo "missing ${AUTH_PY}" >&2
  exit 1
fi

cmd="${1:-login}"
case "${cmd}" in
  --status|status)
    exec python3 "${AUTH_PY}" status
    ;;
  --logout|logout)
    if [[ "$(id -u)" -ne 0 ]]; then
      echo "Re-run as root to remove the credential." >&2
      exit 1
    fi
    auth="/etc/ostree/auth.json"
    if [[ -n "${UNWOKE_AUTH_FILE:-}" ]]; then
      auth="${UNWOKE_AUTH_FILE}"
    fi
    if [[ -f "${auth}" ]]; then
      if command -v shred >/dev/null 2>&1; then
        shred -u "${auth}" || rm -f "${auth}"
      else
        rm -f "${auth}"
      fi
      echo "invite: removed local registry credential"
    else
      echo "invite: no local registry credential"
    fi
    exit 0
    ;;
  --require|login|--login)
    ;;
  *)
    usage
    ;;
esac

if python3 "${AUTH_PY}" status >/dev/null 2>&1; then
  echo "Registry credential is already in place (mode 600)."
  exit 0
fi

if [[ "${cmd}" == "--require" && "${UNWOKE_INVITE_NONINTERACTIVE:-}" == "1" ]]; then
  echo "Invite credential missing." >&2
  exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Re-run as root: sudo /usr/libexec/unwoke/invite-login.sh" >&2
  exit 1
fi

if [[ ! -t 0 || ! -t 1 ]]; then
  echo "No terminal. Run ujust invite-login from a local shell." >&2
  exit 1
fi

echo "GitHub login that the owner invited. The token is a classic PAT with only read:packages."
echo "Fine-grained tokens cannot pull GHCR. The token is not stored in the image."
read -r -p "GitHub username: " invite_user
read -r -s -p "Token: " invite_token
echo
if [[ -z "${invite_user}" || -z "${invite_token}" ]]; then
  echo "Username and token are both required." >&2
  unset invite_user invite_token
  exit 1
fi

export UNWOKE_INVITE_USER="${invite_user}"
export UNWOKE_INVITE_TOKEN="${invite_token}"
unset invite_user invite_token
trap 'unset UNWOKE_INVITE_USER UNWOKE_INVITE_TOKEN' EXIT
python3 "${AUTH_PY}" save
if command -v restorecon >/dev/null 2>&1; then
  restorecon -v "${UNWOKE_AUTH_FILE:-/etc/ostree/auth.json}" || true
fi
