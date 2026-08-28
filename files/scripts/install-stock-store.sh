#!/usr/bin/env bash
# Restore the distro store (GNOME Software / Discover) after Bazaar is gone.
# A second BlueBuild dnf module left $releasever unsubstituted and 404'd Fedora.
set -oue pipefail

. /usr/lib/os-release
ver="${VERSION_ID:-44}"

pkgs=()
if rpm -q gnome-shell >/dev/null 2>&1; then
  pkgs+=(gnome-software)
fi
if rpm -q plasma-workspace >/dev/null 2>&1 || rpm -q plasma-desktop >/dev/null 2>&1; then
  pkgs+=(plasma-discover)
fi

if [[ ${#pkgs[@]} -eq 0 ]]; then
  echo "No GNOME/KDE store package to restore, skipping."
  exit 0
fi

echo "Installing ${pkgs[*]} with --releasever=${ver}"
dnf5 -y --releasever="${ver}" --setopt=skip_if_unavailable=true install "${pkgs[@]}"
