#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with Whonix or secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Gateway then Workstation. qemu:///session. Do not attach extra NICs.
set -euo pipefail
export LIBVIRT_DEFAULT_URI="${LIBVIRT_DEFAULT_URI:-qemu:///session}"

if ! command -v virsh >/dev/null; then
  echo "KVM not layered. ujust install-whonix" >&2
  exit 1
fi
if ! virsh dominfo Whonix-Gateway >/dev/null 2>&1; then
  echo "Whonix not imported. ujust install-whonix" >&2
  exit 1
fi

# Refuse if Workstation gained extra NICs (virt-manager "NAT" leak).
ifaces="$(virsh dumpxml Whonix-Workstation 2>/dev/null | grep -c '<interface' || true)"
if [[ "${ifaces}" -gt 1 ]]; then
  echo "REFUSE: Workstation has extra NICs. That can leak the real IP. Fix XML, then retry." >&2
  exit 1
fi

for n in Whonix-External Whonix-Internal; do
  virsh net-start "$n" >/dev/null 2>&1 || true
done

echo "Starting Whonix-Gateway (Tor)…"
virsh start Whonix-Gateway >/dev/null 2>&1 || true
# Give Tor a moment before the workstation exists.
sleep 8
echo "Starting Whonix-Workstation…"
virsh start Whonix-Workstation >/dev/null 2>&1 || true
if command -v virt-viewer >/dev/null; then
  virt-viewer --attach --connect "${LIBVIRT_DEFAULT_URI}" Whonix-Workstation >/dev/null 2>&1 &
  virt-viewer --attach --connect "${LIBVIRT_DEFAULT_URI}" Whonix-Gateway >/dev/null 2>&1 &
elif command -v virt-manager >/dev/null; then
  echo "Open virt-manager → QEMU/KVM user session (not system)."
  virt-manager >/dev/null 2>&1 &
fi
echo "Work inside Workstation only. Host is still Unwoke clearnet."
