#!/usr/bin/env bash
# Open a Tutorials page. Overlay locks are unchanged.
set -euo pipefail
slug="${1:-}"
base="https://sergi270710267.github.io/unwoke-secureblue/tutorials"
if [[ -n "${slug}" ]]; then
  url="${base}/${slug}/"
else
  url="${base}/"
fi
if command -v xdg-open >/dev/null; then
  xdg-open "${url}" >/dev/null 2>&1 || true
else
  echo "${url}"
fi
