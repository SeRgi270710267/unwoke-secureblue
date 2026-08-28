#!/usr/bin/env bash
# Compile and load the Brave SELinux domain, then put it on secureblue's
# userns allow-list. harden_userns stays enabled.
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

# rpm-ostree compose leaves rpm -q unusable (malformed Name db). Detect by files.
installed_devel=0
if [[ ! -f /usr/share/selinux/devel/Makefile ]]; then
  dnf5 -y --setopt=install_weak_deps=False install selinux-policy-devel
  installed_devel=1
fi

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
cp -a "${POLICY_SRC}/unwoke_brave.te" "${POLICY_SRC}/unwoke_brave.fc" "${work}/"
(
  cd "${work}"
  make -f /usr/share/selinux/devel/Makefile unwoke_brave.pp
)

# Priority 300: above RPM modules (200), below a local admin's default (400).
semodule -v -X 300 -i "${work}/unwoke_brave.pp" "${POLICY_SRC}/unwoke_brave_userns.cil"

if command -v restorecon >/dev/null; then
  restorecon -FR /opt/brave.com/brave-origin /usr/bin/brave-origin 2>/dev/null || true
fi

if [[ "${installed_devel}" -eq 1 ]]; then
  dnf5 -y remove selinux-policy-devel || true
fi

echo "unwoke: Brave Origin SELinux domain loaded; harden_userns left enabled"
semodule -l | grep -E '^(unwoke_brave|harden_userns)$' || true
