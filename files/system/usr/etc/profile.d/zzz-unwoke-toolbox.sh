# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# toolbox/distrobox off until /etc/unwoke/allow-toolbox exists.
# ujust set-toolbox on
if [ -f /etc/unwoke/allow-toolbox ]; then
  return 0 2>/dev/null || true
fi
if [ -d /usr/share/unwoke/blocked-bin ]; then
  PATH="/usr/share/unwoke/blocked-bin${PATH:+:$PATH}"
  export PATH
fi
