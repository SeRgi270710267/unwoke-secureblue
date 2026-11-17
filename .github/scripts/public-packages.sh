#!/usr/bin/env bash
# Compatibility name. This used to set Unwoke packages Public.
# It must never do that again. Invite-only: only report anonymous pulls.
set -u
echo "public-packages: refused to change visibility. Checking anonymous pull instead."
here="$(cd "$(dirname "$0")" && pwd)"
exec bash "${here}/package-visibility.sh"
