#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Compile and load the Brave SELinux domain, then put it on secureblue's
# userns allow-list. harden_userns stays enabled. No dnf install.
set -oue pipefail

POLICY_SRC="/usr/share/unwoke/selinux"
[[ -f "${POLICY_SRC}/unwoke_brave.te" ]] || {
  echo "missing ${POLICY_SRC}/unwoke_brave.te" >&2
  exit 1
}

if [[ ! -e /opt/brave.com/brave-origin/brave ]]; then
  echo "Brave Origin ELF missing at /opt/brave.com/brave-origin/brave" >&2
  ls -la /opt/brave.com 2>/dev/null || true
  ls -la /opt/brave.com/brave-origin 2>/dev/null || true
  exit 1
fi

# Brave Origin RPM often ships chrome-sandbox SUID. Keep the image SUID-less;
# Chromium then uses the namespace sandbox inside brave_t.
if [[ -e /opt/brave.com/brave-origin ]]; then
  find /opt/brave.com/brave-origin -xdev \( -perm -4000 -o -perm -2000 \) -type f -exec chmod a-s {} + 2>/dev/null || true
fi

# Never dnf install selinux-policy-devel (that extra Origin dnf malforms
# Packages). Download RPMs into a throwaway installroot, extract files,
# compile, delete the devel tree. Do not bump titanoboa.
# shellcheck source=/usr/libexec/unwoke/rpm-files-only.sh
source /usr/libexec/unwoke/rpm-files-only.sh

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
cp -a "${POLICY_SRC}/unwoke_brave.te" "${POLICY_SRC}/unwoke_brave.fc" "${work}/"

if [[ ! -f /usr/share/selinux/devel/Makefile ]]; then
  echo "unwoke: extracting selinux-policy-devel (files only)"
  unwoke_rpm_download "${work}/rpms" selinux-policy-devel
  for r in "${work}/rpms"/selinux-policy-devel-*.rpm; do
    [[ -f "${r}" ]] || continue
    unwoke_rpm_extract "${r}" /
  done
fi
[[ -f /usr/share/selinux/devel/Makefile ]] || {
  echo "FAIL: selinux-policy-devel Makefile missing after extract" >&2
  exit 1
}

tools="${work}/tools"
mkdir -p "${tools}"
need_tool() {
  local cmd="$1" pkg="$2"
  if command -v "${cmd}" >/dev/null; then
    return 0
  fi
  echo "unwoke: extracting ${pkg} for ${cmd} (files only)"
  unwoke_rpm_download "${work}/rpms" "${pkg}"
  for r in "${work}/rpms"/${pkg}-*.rpm; do
    [[ -f "${r}" ]] || continue
    unwoke_rpm_extract "${r}" "${tools}"
  done
}
need_tool make make
need_tool m4 m4
need_tool checkmodule checkpolicy
export PATH="${tools}/usr/bin:${tools}/bin:${PATH}"
if [[ -d "${tools}/usr/lib64" ]]; then
  export LD_LIBRARY_PATH="${tools}/usr/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
fi
command -v make >/dev/null || { echo "FAIL: make missing" >&2; exit 1; }
command -v checkmodule >/dev/null || { echo "FAIL: checkmodule missing" >&2; exit 1; }

(
  cd "${work}"
  make -f /usr/share/selinux/devel/Makefile unwoke_brave.pp
)

# Priority 300: above RPM modules (200), below a local admin's default (400).
semodule -v -X 300 -i "${work}/unwoke_brave.pp" "${POLICY_SRC}/unwoke_brave_userns.cil"

if command -v restorecon >/dev/null; then
  restorecon -FR /opt/brave.com/brave-origin /usr/bin/brave-origin 2>/dev/null || true
fi

# Do not leave policy devel headers on the desktop image.
rm -rf /usr/share/selinux/devel

echo "unwoke: Brave Origin SELinux domain loaded; harden_userns left enabled"
semodule -l | grep -E '^(unwoke_brave|harden_userns)$' || true
