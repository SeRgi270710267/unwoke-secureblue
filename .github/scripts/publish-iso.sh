#!/usr/bin/env bash
# Publish one ISO to a private GHCR package. Never upload a public artifact.
# Do not create the package with GITHUB_TOKEN: on a public repository that
# inherits pull access for everyone who can read the repo.
# Do not print tokens.
set -euo pipefail
umask 077

IMAGE_NAME="${IMAGE_NAME:?}"
OWNER="${GITHUB_REPOSITORY_OWNER:?}"
OWNER="${OWNER,,}"
REF="ghcr.io/${OWNER}/${IMAGE_NAME}-iso:latest"
ISO_FILE="${ISO_FILE:-}"

if [[ -z "${ISO_FILE}" || ! -f "${ISO_FILE}" ]]; then
  ISO_FILE="$(find "${GITHUB_WORKSPACE:-.}/output" -name '*.iso' -size +100M | head -n 1 || true)"
fi
if [[ -z "${ISO_FILE}" || ! -f "${ISO_FILE}" ]]; then
  echo "publish-iso: no ISO file" >&2
  exit 1
fi

anon_code() {
  local tok code
  tok="$(curl -fsSL --retry 3 --retry-delay 1 --proto '=https' \
      "https://ghcr.io/token?service=ghcr.io&scope=repository:${OWNER}/${IMAGE_NAME}-iso:pull" \
      | python3 -c 'import json,sys; print(json.load(sys.stdin).get("token",""))' \
      2>/dev/null || true)"
  if [[ -z "${tok}" ]]; then
    echo unknown
    return 0
  fi
  code="$(curl -sS -o /dev/null -w '%{http_code}' --proto '=https' \
      -H "Authorization: Bearer ${tok}" \
      -H "Accept: application/vnd.oci.image.manifest.v1+json" \
      "https://ghcr.io/v2/${OWNER}/${IMAGE_NAME}-iso/manifests/latest" || true)"
  echo "${code}"
}

login() {
  local user="$1"
  local token="$2"
  printf '%s\n' "${token}" | oras login ghcr.io -u "${user}" --password-stdin >/dev/null
}

push_files() {
  local iso_dir iso_base
  local -a files
  iso_dir="$(dirname "${ISO_FILE}")"
  iso_base="$(basename "${ISO_FILE}")"
  files=("${iso_base}:application/vnd.unwoke.iso")
  [[ -s "${iso_dir}/SHA256SUMS" ]] && files+=("SHA256SUMS:text/plain")
  [[ -s "${iso_dir}/SHA256SUMS.sig" ]] && files+=("SHA256SUMS.sig:application/octet-stream")
  (
    cd "${iso_dir}"
    oras push "${REF}" \
      --artifact-type application/vnd.unwoke.iso.v1 \
      "${files[@]}"
  )
}

export PATH="${HOME}/.local/bin:${PATH}"
command -v oras >/dev/null

code="$(anon_code)"
echo "publish-iso: anonymous manifest ${code}"
if [[ "${code}" == "200" ]]; then
  echo "publish-iso: refusing to push; anonymous pull returned 200" >&2
  echo "publish-iso: the -iso package is anonymously readable. This is not a missing GHCR_PUBLISH_TOKEN." >&2
  exit 1
fi

if [[ "${code}" == "404" || "${code}" == "unknown" ]]; then
  if [[ -z "${GHCR_PUBLISH_TOKEN:-}" ]]; then
    echo "::warning title=GHCR ISO not published::GHCR_PUBLISH_TOKEN is unset. The ISO was built and was not published to GHCR. GITHUB_TOKEN is not used to create that package."
    exit 0
  fi
  login "${OWNER}" "${GHCR_PUBLISH_TOKEN}"
else
  if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "publish-iso: no token for an existing package" >&2
    exit 1
  fi
  login "${GITHUB_ACTOR:-${OWNER}}" "${GITHUB_TOKEN}"
fi

push_files
after="$(anon_code)"
echo "publish-iso: anonymous manifest after push ${after}"
if [[ "${after}" == "200" ]]; then
  echo "publish-iso: package is still anonymously readable" >&2
  exit 1
fi

if [[ -n "${COSIGN_PRIVATE_KEY:-}" ]]; then
  export KEY="${RUNNER_TEMP:-/tmp}/unwoke-cosign.key"
  python3 -c 'import os, pathlib; p=pathlib.Path(os.environ["KEY"]); p.write_text(os.environ["COSIGN_PRIVATE_KEY"], encoding="utf-8"); os.chmod(p, 0o600)'
  set +e
  COSIGN_YES=1 COSIGN_OCI_EXPERIMENTAL=0 COSIGN_TLOG_UPLOAD=false \
    cosign sign --yes --tlog-upload=false --key "${KEY}" "${REF}"
  sign_rc=$?
  set -e
  shred -u "${KEY}" || rm -f "${KEY}"
  if [[ "${sign_rc}" -ne 0 ]]; then
    echo "publish-iso: package push succeeded; cosign sign of the tag failed"
  fi
fi

echo "publish-iso: pushed. Turn off Inherit access from repository if this package was just created."
echo "publish-iso: anonymous 401 is not proof. Any GitHub user can pull while inherit stays on."
