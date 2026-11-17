#!/usr/bin/python3
# Unwoke SecureBlue. Not affiliated with secureblue.
# SPDX-License-Identifier: LicenseRef-Unwoke-SA-1.0. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Unwoke trampoline: stock `ujust harden-flatpak` execs this path.
# Do not run upstream's copy. Our script owns the behavior.
import os
import sys

TARGET = "/usr/libexec/unwoke/harden-flatpak.sh"
os.execv(TARGET, [TARGET, *sys.argv[1:]])
