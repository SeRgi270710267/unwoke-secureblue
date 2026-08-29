#!/usr/bin/env bash
# Inspect a *signed* official secureblue image for strings that would only
# make sense if they were targeting this overlay. Does not execute the image.
#
# Cosign still only proves *they* signed it. This catch is: a public base
# that names Unwoke / this GitHub / our overlay paths. A generic backdoor
# that hits every secureblue user, or an obfuscated payload, will not match.
set -euo pipefail

base="${1:?usage: scan-base-canary.sh ghcr.io/secureblue/<image>}"
key="${GITHUB_WORKSPACE:-.}/keys/secureblue.pub"
needles="${GITHUB_WORKSPACE:-.}/.github/scripts/base-canary-needles.txt"
live_key_url="https://raw.githubusercontent.com/secureblue/secureblue/live/cosign.pub"

[[ -f "$key" ]] || { echo "missing vendored key: $key" >&2; exit 1; }
[[ -f "$needles" ]] || { echo "missing needles: $needles" >&2; exit 1; }

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
echo "canary: inspecting ${img} (create/copy only, no run)"

docker pull "${img}"

cid="$(docker create "${img}" /bin/true)"
cleanup() { docker rm -f "${cid}" >/dev/null 2>&1 || true; }
trap cleanup EXIT

work="$(mktemp -d)"
# Stock must not already ship our overlay tree.
if docker cp "${cid}:/usr/share/unwoke" "${work}/unwoke-tree" 2>/dev/null; then
  echo "FAIL: stock base contains /usr/share/unwoke" >&2
  find "${work}/unwoke-tree" | head >&2 || true
  exit 1
fi
if docker cp "${cid}:/usr/libexec/unwoke" "${work}/unwoke-libexec" 2>/dev/null; then
  echo "FAIL: stock base contains /usr/libexec/unwoke" >&2
  exit 1
fi

# Copy likely script/unit locations. Missing paths are fine.
for p in \
  /usr/libexec \
  /usr/lib/systemd \
  /usr/etc \
  /etc \
  /usr/share/ublue-os \
  /usr/share/just \
  /usr/libexec/secureblue
do
  dest="${work}/tree${p}"
  mkdir -p "$(dirname "${dest}")"
  docker cp "${cid}:${p}" "${dest}" 2>/dev/null || true
done

if [[ ! -d "${work}/tree" ]]; then
  echo "FAIL: copied nothing from ${img}" >&2
  exit 1
fi

# -I skips binary. Needles are literal substrings, one per line.
mapfile -t pats < <(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "${needles}")
[[ "${#pats[@]}" -gt 0 ]] || { echo "empty needle list" >&2; exit 1; }

regex="$(printf '%s\n' "${pats[@]}" | sed 's/[.[\*^$()+?{|]/\\&/g' | paste -sd '|')"
echo "canary: searching copied trees for: ${regex}"

hits="$(grep -RInI -E "${regex}" "${work}/tree" || true)"
if [[ -n "${hits}" ]]; then
  echo "FAIL: official base names this overlay (possible targeted payload in a public image)" >&2
  echo "${hits}" | head -n 80 >&2
  echo "Refusing to overlay ${img}" >&2
  exit 1
fi

echo "canary: clean — no Unwoke needles in ${img}"
