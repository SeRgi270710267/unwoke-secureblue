#!/usr/bin/python3
# Unwoke trampoline: stock `ujust harden-flatpak` execs this path.
# Do not run upstream's copy. Our script owns the behavior.
import os
import sys

TARGET = "/usr/libexec/unwoke/harden-flatpak.sh"
os.execv(TARGET, [TARGET, *sys.argv[1:]])
