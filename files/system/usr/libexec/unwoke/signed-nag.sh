#!/usr/bin/env bash
# Repeat until the signed image is the booted origin.
set -euo pipefail
exec /usr/bin/bash /usr/libexec/unwoke/notify-reboot.sh
