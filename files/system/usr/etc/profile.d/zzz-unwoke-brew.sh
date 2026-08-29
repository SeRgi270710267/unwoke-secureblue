# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Homebrew off until /etc/unwoke/allow-brew exists.
# ujust set-brew on
if [ -f /etc/unwoke/allow-brew ]; then
  return 0 2>/dev/null || true
fi
if [ -n "${PATH:-}" ]; then
  PATH="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v -e '/linuxbrew/' -e '/.linuxbrew/' -e '/.homebrew/' | paste -sd: -)"
  export PATH
fi
unset HOMEBREW_PREFIX HOMEBREW_CELLAR HOMEBREW_REPOSITORY HOMEBREW_SHELLENV_PREFIX 2>/dev/null || true
brew() {
  echo "Homebrew is off on Unwoke SecureBlue (tighter than stock). Enable: ujust set-brew on" >&2
  return 127
}
