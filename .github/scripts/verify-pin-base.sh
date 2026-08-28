#!/usr/bin/env bash
# Verify the official secureblue base with THEIR cosign key, then pin this
# build to that digest so :latest cannot move under us mid-build.
set -euo pipefail

recipe="${1:?recipe path required}"
key="${GITHUB_WORKSPACE:-.}/keys/secureblue.pub"
live_key_url="https://raw.githubusercontent.com/secureblue/secureblue/live/cosign.pub"

[[ -f "$recipe" ]] || { echo "missing recipe: $recipe" >&2; exit 1; }
[[ -f "$key" ]] || { echo "missing vendored key: $key" >&2; exit 1; }

curl -fsSL --retry 5 "$live_key_url" -o /tmp/secureblue-live.pub
if ! cmp -s "$key" /tmp/secureblue-live.pub; then
  echo "ERROR: keys/secureblue.pub does not match secureblue/live/cosign.pub" >&2
  echo "Their signing key rotated. Update keys/secureblue.pub after checking their repo." >&2
  diff -u "$key" /tmp/secureblue-live.pub >&2 || true
  exit 1
fi

base="$(awk '/^base-image:/{print $2; exit}' "$recipe")"
[[ -n "$base" ]] || { echo "no base-image in $recipe" >&2; exit 1; }

ref="${base}:latest"
echo "Verifying $ref with official secureblue cosign.pub"
cosign verify --key "$key" "$ref"

digest="$(cosign verify --key "$key" "$ref" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["critical"]["image"]["docker-manifest-digest"])')"
[[ "$digest" == sha256:* ]] || { echo "bad digest: $digest" >&2; exit 1; }

echo "Pinning $recipe -> ${ref}@${digest}"
# BlueBuild FROM is ${base-image}:${image-version}
sed -i -E "s|^image-version:.*|image-version: latest@${digest}|" "$recipe"
grep -E '^(base-image|image-version):' "$recipe"
