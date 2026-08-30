#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Official brave-origin RPM as *files only*. Do not dnf/rpm -i — that
# extra Origin dnf malforms Packages and titanoboa cannot wrap a USB.
# Do not bump titanoboa.
set -oue pipefail

# shellcheck source=/usr/libexec/unwoke/rpm-files-only.sh
source /usr/libexec/unwoke/rpm-files-only.sh

BRAVE_REPO="https://brave-browser-rpm-release.s3.brave.com/x86_64"
BRAVE_KEY_URL="https://brave-browser-rpm-release.s3.brave.com/brave-core.asc"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

echo "unwoke: downloading brave-origin RPM (curl, no dnf, no rpmdb write)"
mkdir -p "${work}/rpms"
unwoke_yum_fetch "${work}/rpms" "${BRAVE_REPO}" brave-origin
rpm="$(find "${work}/rpms" -maxdepth 1 -name 'brave-origin*.rpm' -print | head -n 1)"
[[ -n "${rpm}" && -f "${rpm}" ]] || {
  echo "FAIL: curl did not produce brave-origin*.rpm" >&2
  ls -la "${work}/rpms" >&2 || true
  exit 1
}

curl -fsSL --tlsv1.2 -o "${work}/brave-core.asc" "${BRAVE_KEY_URL}"
unwoke_rpm_verify "${rpm}" "${work}/brave-core.asc"
echo "unwoke: brave-origin RPM GPG ok ($(basename "${rpm}"))"

unwoke_rpm_extract "${rpm}" /
# ostree/Brave RPM payload is /usr/lib/opt/..., not /opt/...
if [[ -e /usr/lib/opt/brave.com/brave-origin/brave && ! -e /opt/brave.com/brave-origin/brave ]]; then
  mkdir -p /opt/brave.com
  ln -sfn /usr/lib/opt/brave.com/brave-origin /opt/brave.com/brave-origin
fi
if [[ ! -e /usr/bin/brave-origin ]]; then
  if [[ -e /usr/bin/brave-origin-stable ]]; then
    ln -sfn brave-origin-stable /usr/bin/brave-origin
  elif [[ -e /usr/lib/opt/brave.com/brave-origin/brave ]]; then
    ln -sfn /usr/lib/opt/brave.com/brave-origin/brave /usr/bin/brave-origin
  fi
fi
[[ -e /opt/brave.com/brave-origin/brave || -e /usr/lib/opt/brave.com/brave-origin/brave || -e /usr/bin/brave-origin ]] || {
  echo "FAIL: extract left no Brave Origin ELF" >&2
  ls -la /opt/brave.com /usr/lib/opt/brave.com /usr/bin/brave-origin* >&2 || true
  exit 1
}
echo "unwoke: brave-origin files extracted (not registered in RPM db)"
# Do not dnf Fedora extras here. Bake fac79ef died pulling libXScrnSaver
# through a throwaway installroot that inherited secureblue.repo GPG.
# USB wrap does not need libXss. Tray/screensaver libs can come later.
