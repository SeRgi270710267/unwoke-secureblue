#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Bake Unwoke wallpaper / accent into the image (GNOME schemas already compiled).
set -oue pipefail
exec /usr/libexec/unwoke/theme.sh apply-build
