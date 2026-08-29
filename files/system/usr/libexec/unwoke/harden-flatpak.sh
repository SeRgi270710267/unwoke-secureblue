#!/usr/bin/env bash
# Unwoke stand-in for stock `ujust harden-flatpak` (global).
# Stock ujust execs /usr/libexec/secureblue/harden_flatpak.py; that file is
# an Unwoke trampoline that execs this script. Do not run upstream Python.
# Behavior last reviewed against files/upstream-snapshots/secureblue/harden_flatpak.py
# (highest hwcap libhardened_malloc.so, host-os:ro, ELECTRON_OZONE_PLATFORM_HINT=auto).
set -euo pipefail

command -v flatpak >/dev/null || exit 0

best_uarch() {
  local info
  [[ -x /usr/lib64/ld-linux-x86-64.so.2 ]] || { printf ''; return 0; }
  info="$(/usr/lib64/ld-linux-x86-64.so.2 --help 2>/dev/null || true)"
  printf '%s\n' "${info}" | sed -n 's/^[[:space:]]*\(x86-64-v[0-9][0-9]*\).*(supported, searched).*/\1/p' | head -n1
}

uarch="$(best_uarch)"
dir="/var/run/host/usr/lib64"
if [[ -n "${uarch}" ]]; then
  dir="${dir}/glibc-hwcaps/${uarch}"
fi
lib="${dir}/libhardened_malloc.so"

flatpak override --user \
  --filesystem=host-os:ro \
  --env=LD_PRELOAD="${lib}" \
  --env=ELECTRON_OZONE_PLATFORM_HINT=auto
