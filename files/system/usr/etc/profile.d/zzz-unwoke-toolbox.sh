# toolbox/distrobox off until /etc/unwoke/allow-toolbox exists.
# ujust set-toolbox on
if [ -f /etc/unwoke/allow-toolbox ]; then
  return 0 2>/dev/null || true
fi
if [ -d /usr/share/unwoke/blocked-bin ]; then
  PATH="/usr/share/unwoke/blocked-bin${PATH:+:$PATH}"
  export PATH
fi
