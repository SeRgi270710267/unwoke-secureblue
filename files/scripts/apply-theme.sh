#!/usr/bin/env bash
# Bake Unwoke wallpaper / accent into the image (GNOME schemas already compiled).
set -oue pipefail
exec /usr/libexec/unwoke/theme.sh apply-build
