# Unwoke SecureBlue. Not affiliated with secureblue.
# SPDX-License-Identifier: LicenseRef-Unwoke-SA-1.0. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# shellcheck shell=sh
# toolbox/distrobox off until /etc/unwoke/allow-toolbox exists.
# ujust set-toolbox on
if [ -f /etc/unwoke/allow-toolbox ]; then
  return 0 2>/dev/null || true
fi
if [ -d /usr/share/unwoke/blocked-bin ]; then
  # shellcheck disable=SC2123
  PATH="/usr/share/unwoke/blocked-bin${PATH:+:$PATH}"
  export PATH
fi
