#!/usr/bin/env bash
# Run ShellCheck on every tracked shell script.
# SC2034 in sourced libraries is disabled in those files, not here.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "${root}"

if ! command -v shellcheck >/dev/null; then
  echo "shellcheck is not installed" >&2
  exit 1
fi

mapfile -t files < <(git ls-files '*.sh')
if [[ "${#files[@]}" -eq 0 ]]; then
  echo "shellcheck: no scripts" >&2
  exit 1
fi

shellcheck -S warning "${files[@]}"
echo "shellcheck: ok ${#files[@]} files"
