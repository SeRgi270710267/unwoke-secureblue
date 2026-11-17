#!/usr/bin/env bash
# Decide whether a GHCR push is allowed, and with which token.
# preflight writes use_publish=true|false to GITHUB_OUTPUT.
#   true  = package is missing; the caller must push with GHCR_PUBLISH_TOKEN.
#   false = package exists and an anonymous pull is not 200; GITHUB_TOKEN may push.
# Missing token on a create, or anonymous 200, exits 1. Tokens are not printed.
# post exits 1 if an anonymous pull of :latest is 200 after the push.
#
#   ghcr-push-guard.sh preflight|post
#   ghcr-push-guard.sh --selftest
set -euo pipefail

OWNER="${GITHUB_REPOSITORY_OWNER:-sergi270710267}"
OWNER="${OWNER,,}"

anon_http() {
  local path="$1"
  local tok code
  tok="$(curl -fsSL --retry 3 --retry-delay 1 --proto '=https' \
      "https://ghcr.io/token?service=ghcr.io&scope=repository:${OWNER}/${IMAGE_NAME}:pull" \
      | python3 -c 'import json,sys; print(json.load(sys.stdin).get("token",""))' \
      2>/dev/null || true)"
  if [[ -z "${tok}" ]]; then
    echo unknown
    return 0
  fi
  code="$(curl -sS -o /dev/null -w '%{http_code}' --proto '=https' \
      -H "Authorization: Bearer ${tok}" \
      -H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json" \
      "https://ghcr.io/v2/${OWNER}/${IMAGE_NAME}${path}" || true)"
  echo "${code}"
}

# manifest and tag list. 200 on either means the world can read the package.
anon_code() {
  local manifest tags
  manifest="$(anon_http "/manifests/latest")"
  tags="$(anon_http "/tags/list")"
  if [[ "${manifest}" == "200" || "${tags}" == "200" ]]; then
    echo 200
    return 0
  fi
  if [[ "${manifest}" == "404" && ( "${tags}" == "404" || "${tags}" == "unknown" ) ]]; then
    echo 404
    return 0
  fi
  if [[ "${manifest}" == "unknown" && "${tags}" == "unknown" ]]; then
    echo unknown
    return 0
  fi
  echo "${manifest}"
}

decide() {
  local code="$1"
  local has_publish="$2"
  if [[ "${code}" == "200" ]]; then
    echo "ghcr-push-guard: refusing to push; anonymous pull returned 200" >&2
    return 1
  fi
  if [[ "${code}" == "404" || "${code}" == "unknown" ]]; then
    if [[ "${has_publish}" != "yes" ]]; then
      echo "ghcr-push-guard: ${IMAGE_NAME} does not exist and GHCR_PUBLISH_TOKEN is unset." >&2
      echo "ghcr-push-guard: refusing to create it with GITHUB_TOKEN. A GITHUB_TOKEN push from this public repository creates a package the world can pull." >&2
      return 1
    fi
    echo true
    return 0
  fi
  echo false
  return 0
}

selftest() {
  local ok=0
  IMAGE_NAME="unwoke-selftest"
  if decide 200 yes >/dev/null; then
    echo "selftest FAIL public push allowed" >&2
    ok=1
  fi
  if decide 404 no >/dev/null; then
    echo "selftest FAIL create without token allowed" >&2
    ok=1
  fi
  if [[ "$(decide 404 yes)" != "true" ]]; then
    echo "selftest FAIL create with token" >&2
    ok=1
  fi
  if [[ "$(decide 401 yes)" != "false" ]]; then
    echo "selftest FAIL private package" >&2
    ok=1
  fi
  if [[ "${ok}" -eq 0 ]]; then
    echo "ghcr-push-guard selftest ok"
  fi
  return "${ok}"
}

if [[ "${1:-}" == "--selftest" ]]; then
  selftest
  exit $?
fi

mode="${1:?usage: ghcr-push-guard.sh preflight|post|--selftest}"
IMAGE_NAME="${IMAGE_NAME:?}"
code="$(anon_code)"
echo "ghcr-push-guard: ${IMAGE_NAME} anonymous ${code}"

case "${mode}" in
  preflight)
    has="no"
    [[ -n "${GHCR_PUBLISH_TOKEN:-}" ]] && has="yes"
    use="$(decide "${code}" "${has}")"
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
      echo "use_publish=${use}" >> "${GITHUB_OUTPUT}"
    else
      echo "use_publish=${use}"
    fi
    ;;
  post)
    if [[ "${code}" == "200" ]]; then
      echo "ghcr-push-guard: anonymous pull returned 200 after the push" >&2
      exit 1
    fi
    if [[ "${code}" == "404" || "${code}" == "unknown" ]]; then
      echo "ghcr-push-guard: could not confirm the push is closed (${code})" >&2
      exit 1
    fi
    echo "ghcr-push-guard: anonymous pull denied (${code})"
    ;;
  *)
    echo "usage: ghcr-push-guard.sh preflight|post|--selftest" >&2
    exit 2
    ;;
esac
