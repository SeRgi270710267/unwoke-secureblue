#!/usr/bin/env bash
# Inspect a *signed* official secureblue image for strings that would only
# make sense if they were targeting this overlay. Does not execute the image.
# Uses crane export (not docker pull): Atomic images exceed Docker's ~125 layer depth.
set -euo pipefail

base="${1:?usage: scan-base-canary.sh ghcr.io/secureblue/<image>}"
key="${GITHUB_WORKSPACE:-.}/keys/secureblue.pub"
needles="${GITHUB_WORKSPACE:-.}/.github/scripts/base-canary-needles.txt"
extract="${GITHUB_WORKSPACE:-.}/.github/scripts/extract-prefixes.py"
live_key_url="https://raw.githubusercontent.com/secureblue/secureblue/live/cosign.pub"

[[ -f "$key" ]] || { echo "missing vendored key: $key" >&2; exit 1; }
[[ -f "$needles" ]] || { echo "missing needles: $needles" >&2; exit 1; }
[[ -f "$extract" ]] || { echo "missing $extract" >&2; exit 1; }

bash "${GITHUB_WORKSPACE:-.}/.github/scripts/install-crane.sh"
export PATH="${HOME}/.local/bin:${PATH}"

curl -fsSL --retry 5 "$live_key_url" -o /tmp/secureblue-live.pub
if ! cmp -s "$key" /tmp/secureblue-live.pub; then
  echo "ERROR: keys/secureblue.pub does not match secureblue/live/cosign.pub" >&2
  echo "Their signing key rotated. Do not overlay. Check their repo out of band." >&2
  exit 1
fi

ref="${base}:latest"
echo "canary: verifying ${ref}"
cosign verify --key "$key" "$ref" >/dev/null

digest="$(cosign verify --key "$key" "$ref" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["critical"]["image"]["docker-manifest-digest"])')"
[[ "${digest}" == sha256:* ]] || { echo "bad digest: ${digest}" >&2; exit 1; }
img="${base}@${digest}"
echo "canary: exporting ${img} (crane, no run, no docker pull)"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

crane export "${img}" - | python3 "${extract}" "${work}" "${work}/members.txt" \
  usr/libexec usr/lib/systemd usr/etc etc usr/share/ublue-os usr/share/just \
  usr/share/unwoke usr/bin usr/sbin

if [[ ! -s "${work}/members.txt" ]]; then
  echo "FAIL: export produced no file list from ${img}" >&2
  exit 1
fi

if [[ -d "${work}/usr/share/unwoke" ]]; then
  echo "FAIL: stock base contains /usr/share/unwoke" >&2
  ls -la "${work}/usr/share/unwoke" >&2 || true
  exit 1
fi
if [[ -d "${work}/usr/libexec/unwoke" ]]; then
  echo "FAIL: stock base contains /usr/libexec/unwoke" >&2
  exit 1
fi

mapfile -t pats < <(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "${needles}")
[[ "${#pats[@]}" -gt 0 ]] || { echo "empty needle list" >&2; exit 1; }

regex="$(printf '%s\n' "${pats[@]}" | sed 's/[.[\*^$()+?{|]/\\&/g' | paste -sd '|')"
echo "canary: searching names + extracted trees for: ${regex}"

hits="$(grep -RInI -E "${regex}" "${work}/members.txt" "${work}" --exclude=members.txt || true)"
if [[ -n "${hits}" ]]; then
  echo "FAIL: official base names this overlay (possible targeted payload in a public image)" >&2
  echo "${hits}" | sed -n '1,80p' >&2
  echo "Refusing to overlay ${img}" >&2
  exit 1
fi

echo "canary: clean — no Unwoke needles in ${img}"
