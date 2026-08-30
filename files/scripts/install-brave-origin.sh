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

echo "unwoke: downloading brave-origin RPM (files only, no rpmdb write)"
cat > "${work}/brave-browser.repo" <<EOF
[brave-browser]
name=Brave Browser
enabled=1
gpgcheck=0
baseurl=${BRAVE_REPO}
EOF

# Isolated installroot + this repo only for the Brave NEVRA.
root="$(mktemp -d)"
fedora="$(unwoke_rpm_fedora)"
mkdir -p \
  "${root}/usr/lib/sysimage/rpm" \
  "${root}/etc/yum.repos.d" \
  "${root}/etc/dnf/vars" \
  "${root}/var/cache" \
  "${work}/rpms"
rpm --initdb --dbpath "${root}/usr/lib/sysimage/rpm"
printf '%s\n' "${fedora}" > "${root}/etc/dnf/vars/releasever"
cp -a "${work}/brave-browser.repo" "${root}/etc/yum.repos.d/"
dnf5 --installroot="${root}" --releasever="${fedora}" \
  --setopt=cachedir="${root}/var/cache/libdnf5" \
  --setopt=keepcache=True \
  --nogpgcheck \
  download --destdir="${work}/rpms" brave-origin
rm -rf "${root}"

rpm="$(find "${work}/rpms" -maxdepth 1 -name 'brave-origin-*.rpm' -print | head -n 1)"
[[ -n "${rpm}" && -f "${rpm}" ]] || {
  echo "FAIL: dnf5 download did not produce brave-origin-*.rpm" >&2
  ls -la "${work}/rpms" >&2 || true
  exit 1
}

curl -fsSL --tlsv1.2 -o "${work}/brave-core.asc" "${BRAVE_KEY_URL}"
unwoke_rpm_verify "${rpm}" "${work}/brave-core.asc"
echo "unwoke: brave-origin RPM GPG ok ($(basename "${rpm}"))"

unwoke_rpm_extract "${rpm}" /
[[ -e /opt/brave.com/brave-origin/brave ]] || {
  echo "FAIL: extract left no /opt/brave.com/brave-origin/brave" >&2
  exit 1
}
echo "unwoke: brave-origin files extracted (not registered in RPM db)"

# Fedora runtime bits Brave wants. Extract only if the file is missing.
# Isolated dnf5 download — still no image dnf install.
need_so() {
  local n="$1"
  [[ -e "/usr/lib64/${n}" || -e "/usr/lib/${n}" ]]
}
if ! need_so libXss.so.1; then
  echo "unwoke: extracting libXScrnSaver (libXss missing)"
  unwoke_rpm_download "${work}/deps" libXScrnSaver
  for r in "${work}/deps"/libXScrnSaver-*.rpm; do
    [[ -f "${r}" ]] || continue
    unwoke_rpm_extract "${r}" /
  done
fi
if ! need_so libappindicator3.so.1 && ! need_so libayatana-appindicator3.so.1; then
  echo "unwoke: extracting libappindicator-gtk3 (tray lib missing)"
  unwoke_rpm_download "${work}/deps" libappindicator-gtk3 || \
    unwoke_rpm_download "${work}/deps" libayatana-appindicator-gtk3 || true
  for r in "${work}/deps"/lib*appindicator*.rpm; do
    [[ -f "${r}" ]] || continue
    unwoke_rpm_extract "${r}" /
  done
fi
