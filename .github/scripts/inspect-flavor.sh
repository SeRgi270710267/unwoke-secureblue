#!/usr/bin/env bash
# Inspect a published Unwoke GHCR image without docker/podman pull (crane export).
# Usage: inspect-flavor.sh <image-name>   e.g. unwoke-silverblue-trivalent
set -euo pipefail

NAME="${1:?usage: inspect-flavor.sh unwoke-silverblue}"
OWNER="${GITHUB_REPOSITORY_OWNER:-sergi270710267}"
OWNER="${OWNER,,}"
IMG="ghcr.io/${OWNER}/${NAME}:latest"
ROOT="${GITHUB_WORKSPACE:-.}"
PUB="${ROOT}/cosign.pub"
extract="${ROOT}/.github/scripts/extract-prefixes.py"

[[ -f "${PUB}" ]] || { echo "missing ${PUB}" >&2; exit 1; }
[[ -f "${extract}" ]] || { echo "missing ${extract}" >&2; exit 1; }
command -v cosign >/dev/null || { echo "cosign required" >&2; exit 1; }

bash "${ROOT}/.github/scripts/install-crane.sh"
export PATH="${HOME}/.local/bin:${PATH}"

ok=0
for n in 1 2 3 4 5; do
  if crane digest "${IMG}" >/dev/null 2>&1; then
    ok=1
    break
  fi
  echo "inspect: waiting for ${IMG} (${n}/5)"
  sleep 15
done
[[ "${ok}" -eq 1 ]] || { echo "FAIL: cannot see ${IMG}" >&2; exit 1; }

echo "inspect: cosign verify ${IMG}"
# GitHub attest-build-provenance attaches certificate attestations as OCI
# referrers. Newer cosign verify --key can pick those and fail with
# "expected key signature, not certificate". Prefer classic .sig tags.
extra=()
if cosign verify --help 2>&1 | grep -q -- '--new-bundle-format'; then
  extra+=(--new-bundle-format=false)
fi
payload="$(COSIGN_OCI_EXPERIMENTAL=0 cosign verify --key "${PUB}" "${extra[@]}" "${IMG}" 2>/dev/null || true)"
if [[ -z "${payload}" ]]; then
  echo "FAIL: no Unwoke key signature on ${IMG}" >&2
  COSIGN_OCI_EXPERIMENTAL=0 cosign verify --key "${PUB}" "${extra[@]}" "${IMG}" >/dev/null
  exit 1
fi
got="$(python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["critical"]["image"]["docker-manifest-digest"])' <<<"${payload}")"
want="$(crane digest "${IMG}")"
if [[ "${got}" != "${want}" ]]; then
  echo "FAIL: signed digest ${got} != ${want}" >&2
  exit 1
fi
echo "inspect: signed digest ${got}"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
echo "inspect: export ${IMG}"
crane export "${IMG}" - | python3 "${extract}" "${work}" "${work}/members.txt" \
  usr/share/unwoke usr/bin usr/lib64 usr/libexec opt usr/share/applications \
  etc/selinux usr/etc

if [[ ! -s "${work}/members.txt" ]]; then
  echo "FAIL: export produced no file list from ${IMG}" >&2
  exit 1
fi

flavor=""
if [[ -f "${work}/usr/share/unwoke/flavor" ]]; then
  flavor="$(tr -d '[:space:]' < "${work}/usr/share/unwoke/flavor")"
fi
echo "flavor file: ${flavor:-MISSING}"

has() { [[ -e "${work}/$1" ]]; }
# Tar member exists as a file/symlink/hardlink (empty leftover dirs do not count).
listed() {
  awk -F '\t' -v p="$1" '$1 != "dir" && $2 == p { found=1 } END { exit !found }' \
    "${work}/members.txt"
}

fail=0
for d in usr/share/applications/io.github.kolunmi.Bazaar.desktop \
         usr/share/applications/org.gnome.Software.desktop \
         usr/share/applications/org.kde.discover.desktop; do
  if has "$d" && ! grep -q '^Hidden=true' "${work}/${d}" 2>/dev/null; then
    echo "FAIL: store launcher visible: $d" >&2
    fail=1
  fi
done
if listed opt/brave.com/brave/brave; then
  echo "FAIL: full brave-browser ELF present" >&2
  fail=1
fi

tramp="${work}/usr/libexec/secureblue/harden_flatpak.py"
if [[ ! -f "${tramp}" ]] || ! grep -q '/usr/libexec/unwoke/harden-flatpak.sh' "${tramp}"; then
  echo "FAIL: stock harden_flatpak trampoline missing or not ours" >&2
  fail=1
fi
if [[ ! -f "${work}/usr/libexec/unwoke/harden-flatpak.sh" ]]; then
  echo "FAIL: missing /usr/libexec/unwoke/harden-flatpak.sh" >&2
  fail=1
fi

selinux_mentions_origin() {
  grep -R -q '/opt/brave.com/brave-origin' \
    "${work}/etc/selinux" "${work}/usr/etc/selinux" 2>/dev/null
}

case "${NAME}" in
  *trivalent*)
    [[ "${flavor}" == "trivalent" ]] || { echo "FAIL: flavor != trivalent (${flavor})" >&2; fail=1; }
    if ! listed usr/bin/trivalent && ! listed usr/lib64/trivalent/trivalent; then
      echo "FAIL: Trivalent binary missing" >&2
      fail=1
    fi
    if listed opt/brave.com/brave-origin/brave; then
      echo "FAIL: Origin ELF on trivalent image" >&2
      fail=1
    fi
    if selinux_mentions_origin; then
      echo "FAIL: brave-origin in SELinux file_contexts" >&2
      fail=1
    fi
    echo "OK: trivalent flavor checks"
    ;;
  *browserless*)
    [[ "${flavor}" == "browserless" ]] || { echo "FAIL: flavor != browserless (${flavor})" >&2; fail=1; }
    if listed opt/brave.com/brave-origin/brave; then
      echo "FAIL: Origin ELF on browserless image" >&2
      fail=1
    fi
    if listed usr/bin/trivalent || listed usr/lib64/trivalent/trivalent; then
      echo "FAIL: Trivalent present on browserless image" >&2
      fail=1
    fi
    if selinux_mentions_origin; then
      echo "FAIL: brave-origin in SELinux file_contexts" >&2
      fail=1
    fi
    echo "OK: browserless flavor checks"
    ;;
  *)
    [[ "${flavor}" == "brave-origin" ]] || { echo "FAIL: flavor != brave-origin (${flavor})" >&2; fail=1; }
    if listed usr/bin/trivalent || listed usr/lib64/trivalent/trivalent; then
      echo "FAIL: Trivalent present on Origin image" >&2
      fail=1
    fi
    if ! listed opt/brave.com/brave-origin/brave && ! listed usr/bin/brave-origin; then
      echo "FAIL: Origin ELF missing" >&2
      fail=1
    fi
    if ! has usr/share/unwoke/selinux/unwoke_brave.te; then
      echo "FAIL: missing unwoke_brave.te" >&2
      fail=1
    fi
    if [[ -d "${work}/opt/brave.com" ]]; then
      suid="$(find "${work}/opt/brave.com" -xdev -perm -4000 -type f 2>/dev/null || true)"
      if [[ -n "${suid}" ]]; then
        echo "FAIL: SUID remains under /opt/brave.com" >&2
        printf '%s\n' "${suid}" >&2
        fail=1
      fi
    fi
    echo "OK: Origin flavor checks"
    ;;
esac

if [[ "${fail}" -ne 0 ]]; then
  echo "inspect FAILED for ${IMG}" >&2
  echo "matching members:" >&2
  awk -F '\t' '$2 ~ /(trivalent|brave-origin|brave\/brave)/ { print; n++; if (n>=40) exit }' \
    "${work}/members.txt" >&2 || true
  exit 1
fi
echo "inspect OK: ${IMG}"
