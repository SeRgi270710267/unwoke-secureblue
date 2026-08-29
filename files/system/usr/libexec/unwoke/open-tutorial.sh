#!/usr/bin/env bash
# Open a tutorial: local copy first (offline), then the site.
set -euo pipefail
slug="${1:-}"
help_root="/usr/share/unwoke/help"
base="https://sergi270710267.github.io/unwoke-secureblue/tutorials"
if [[ -n "${slug}" && -f "${help_root}/${slug}/index.html" ]]; then
  url="file://${help_root}/${slug}/index.html"
elif [[ -z "${slug}" && -f "${help_root}/index.html" ]]; then
  url="file://${help_root}/index.html"
elif [[ -n "${slug}" ]]; then
  url="${base}/${slug}/"
else
  url="${base}/"
fi
if command -v xdg-open >/dev/null; then
  xdg-open "${url}" >/dev/null 2>&1 || true
else
  echo "${url}"
fi
