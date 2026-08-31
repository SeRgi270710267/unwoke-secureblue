#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Generic strict installer for EVERY vendors{} key. New app = JSON stanza.
# Proton/IVPN menus still exist; they are not the watch list.
set -euo pipefail
VENDOR="/usr/libexec/unwoke/vendor.py"

ask() {
  local prompt="$1" def="${2:-N}"
  local ans=""
  read -r -p "${prompt} [${def}] " ans || true
  ans="${ans:-$def}"
  [[ "${ans}" == [yY] ]]
}

open_url() {
  local url="$1"
  echo "Opening ${url}"
  if command -v xdg-open >/dev/null; then
    xdg-open "${url}" >/dev/null 2>&1 || echo "Open in Trivalent: ${url}"
  else
    echo "Open in Trivalent: ${url}"
  fi
}

spec_get() {
  python3 - "$1" "$2" <<'PY'
import json, sys
name, key = sys.argv[1], sys.argv[2]
spec = json.loads(open("/usr/share/unwoke/vendor-installers.json", encoding="utf-8").read())["vendors"][name]
v = spec.get(key)
if v is None:
    sys.exit(0)
if isinstance(v, list):
    print("\n".join(str(x) for x in v))
elif isinstance(v, bool):
    print("1" if v else "0")
else:
    print(v)
PY
}

ostree_install() {
  local pkg="$1"
  if [[ "$(id -u)" -eq 0 ]]; then
    rpm-ostree install "${pkg}"
  else
    run0 rpm-ostree install "${pkg}"
  fi
}

do_https() {
  local name="$1"
  open_url "$(spec_get "${name}" url)"
}

do_wireguard() {
  local name="$1"
  echo "WireGuard import (strictest native tunnel). No extra daemon."
  echo "Download a .conf (GNOME: filename ≤ 15 chars), then:"
  echo "  Settings → Network → VPN → Import"
  echo "  or: nmcli connection import type wireguard file /path/to/short.conf"
  echo "DNS: keep the VPN resolver. Do not enable Trivalent DoH."
  open_url "$(spec_get "${name}" url)"
}

do_rpm_json() {
  local name="$1" title
  title="$(spec_get "${name}" title)"
  echo "Official RPM + SHA512 for ${title}."
  echo "Not the strictest path if a web/WireGuard option exists."
  echo "Electron-class apps may need: ujust set-unconfined-userns on"
  if ! ask "Download, verify checksum, then rpm-ostree install?" "n"; then
    echo "Aborted."
    return 0
  fi
  if ask "Allow unconfined userns if needed (default No)?" "n"; then
    ujust set-unconfined-userns on || true
  fi
  local ver url sha
  mapfile -t meta < <(python3 "${VENDOR}" pick "${name}")
  ver="${meta[0]:-}"
  url="${meta[1]:-}"
  sha="${meta[2]:-}"
  [[ -n "${url}" && -n "${sha}" ]] || { echo "FAIL: no RPM+checksum" >&2; return 1; }
  echo "Version ${ver}"
  echo "URL ${url}"
  local tmp rpm
  tmp="$(mktemp -d)"
  rpm="${tmp}/pkg.rpm"
  curl -fsSL --tlsv1.2 -o "${rpm}" "${url}"
  echo "${sha}  ${rpm}" | sha512sum --check --strict || echo "${sha}  ${rpm}" | sha256sum --check --strict
  echo "Checksum OK."
  if ! ask "Layer this RPM (reboot)?" "n"; then
    rm -rf "${tmp}"
    return 0
  fi
  ostree_install "${rpm}"
  rm -rf "${tmp}"
  # shellcheck source=/usr/libexec/unwoke/continue-ostree.sh
  source /usr/libexec/unwoke/continue-ostree.sh
  unwoke_write_continue vendor "${name}"
  echo "Reboot. Next login resumes this installer. Or reboot now."
  if ask "Reboot now?" "n"; then
    systemctl reboot
  fi
}

do_yum_repo() {
  local name="$1"
  echo "Official yum/dnf repo (extra RPM origin on Atomic)."
  if ! ask "Add this signed repo and layer packages?" "n"; then
    echo "Aborted."
    return 0
  fi
  local repo tmp
  repo="$(spec_get "${name}" url)"
  tmp="$(mktemp)"
  curl -fsSL --tlsv1.2 -o "${tmp}" "${repo}"
  cat "${tmp}"
  if ! grep -qi 'gpgcheck=1' "${tmp}" && ! grep -qi 'repo_gpgcheck=1' "${tmp}"; then
    echo "FAIL: repo missing gpgcheck=1" >&2
    rm -f "${tmp}"
    return 1
  fi
  if [[ "$(id -u)" -eq 0 ]]; then
    cp "${tmp}" /etc/yum.repos.d/"${name}".repo
    rpm-ostree refresh-md || true
  else
    run0 cp "${tmp}" /etc/yum.repos.d/"${name}".repo
    run0 rpm-ostree refresh-md || true
  fi
  rm -f "${tmp}"
  local pkg
  while IFS= read -r pkg; do
    [[ -n "${pkg}" ]] || continue
    ostree_install "${pkg}"
  done < <(spec_get "${name}" packages)
  while IFS= read -r pkg; do
    [[ -n "${pkg}" ]] || continue
    if ask "Also layer optional ${pkg}?" "n"; then
      ostree_install "${pkg}"
    fi
  done < <(spec_get "${name}" packages_optional)
  # shellcheck source=/usr/libexec/unwoke/continue-ostree.sh
  source /usr/libexec/unwoke/continue-ostree.sh
  unwoke_write_continue vendor "${name}"
  echo "Reboot. Next login resumes this installer."
  if ask "Reboot now?" "n"; then
    systemctl reboot
  fi
}

run_one() {
  local name="$1" kind
  kind="$(spec_get "${name}" kind)"
  echo
  echo "=== ${name}  ($(spec_get "${name}" title))  kind=${kind} ==="
  case "${kind}" in
    https-ok) do_https "${name}" ;;
    wireguard-import) do_wireguard "${name}" ;;
    proton-version-json) do_rpm_json "${name}" ;;
    yum-repo) do_yum_repo "${name}" ;;
    *) echo "unknown kind ${kind}" >&2; return 1 ;;
  esac
}

if [[ "${1:-}" == "--list" || "${1:-}" == "list" ]]; then
  python3 "${VENDOR}" list
  exit 0
fi

if [[ -n "${1:-}" ]]; then
  run_one "$1"
  exit 0
fi

echo "Strict apps (every vendors{} key — watched + healed)."
echo "Nothing auto-unlocks. Flathub unverified is never used."
echo
mapfile -t rows < <(python3 "${VENDOR}" list)
i=0
declare -a keys=()
for row in "${rows[@]}"; do
  i=$((i + 1))
  key="${row%%$'\t'*}"
  rest="${row#*$'\t'}"
  keys+=("${key}")
  echo "  ${i}) ${rest//$'\t'/ — }"
done
echo "  t) Tutorial hub"
echo "  q) Quit"
echo
read -r -p "Choice: " ans || exit 0
case "${ans}" in
  t|T) bash /usr/libexec/unwoke/open-tutorial.sh || true; exit 0 ;;
  q|Q|"") exit 0 ;;
esac
[[ "${ans}" =~ ^[0-9]+$ ]] || { echo "Unknown."; exit 0; }
idx=$((ans - 1))
[[ "${idx}" -ge 0 && "${idx}" -lt "${#keys[@]}" ]] || { echo "Unknown."; exit 0; }
run_one "${keys[$idx]}"
