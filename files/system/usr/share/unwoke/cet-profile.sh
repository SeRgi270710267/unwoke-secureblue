# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Unwoke: Intel CET (SHSTK + IBT). Revert: ujust set-cet off
export GLIBC_TUNABLES="${GLIBC_TUNABLES:+$GLIBC_TUNABLES:}glibc.cpu.x86_shstk=on:glibc.cpu.x86_ibt=on"
