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

guard="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ghcr-push-guard.sh"
if [[ -z "${GITHUB_OUTPUT:-}" ]]; then
  GITHUB_OUTPUT="$(mktemp)"
  export GITHUB_OUTPUT
fi
GHCR_CREATE=skip IMAGE_NAME="${IMAGE_NAME}-iso" bash "${guard}" preflight
use_publish="$(grep '^use_publish=' "${GITHUB_OUTPUT}" | tail -n 1 | cut -d= -f2-)"
if [[ "${use_publish}" == "skip" ]]; then
  echo "publish-iso: GHCR package was not created. The R2 upload does not need it."
  exit 0
fi
if [[ "${use_publish}" == "true" ]]; then
  login "${OWNER}" "${GHCR_PUBLISH_TOKEN}"
else
  if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "publish-iso: no token for an existing package" >&2
    exit 1
  fi
  login "${GITHUB_ACTOR:-${OWNER}}" "${GITHUB_TOKEN}"
fi

push_files
IMAGE_NAME="${IMAGE_NAME}-iso" bash "${guard}" post

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
