#!/usr/bin/env bash
# Decide whether a GHCR push is allowed, and with which token.
# preflight writes use_publish=true|false to GITHUB_OUTPUT.
#   true  = package is missing; the caller must push with GHCR_PUBLISH_TOKEN.
#   false = package exists and the anonymous pull token cannot read it; GITHUB_TOKEN may push.
# Missing token on a create, or anonymous 200, exits 1. Tokens are not printed.
# post exits 1 if an anonymous pull of :latest is 200 after the push.
#
#   ghcr-push-guard.sh preflight|post
#   ghcr-push-guard.sh --selftest
set -euo pipefail

OWNER="${GITHUB_REPOSITORY_OWNER:-sergi270710267}"
OWNER="${OWNER,,}"

# 200 = anonymously readable. 401 = exists and asks for a login.
# 404 = GHCR will not issue a pull token (the name is not a package).
# A bare manifest 401 is not proof of privacy. Public packages return that
# challenge, then 200 once the anonymous pull token is sent.
anon_code() {
  local body token_code tok manifest tags bare
  body="$(mktemp)"
  token_code="$(curl -sS -o "${body}" -w '%{http_code}' --retry 3 --retry-delay 1 --proto '=https' \
      "https://ghcr.io/token?service=ghcr.io&scope=repository:${OWNER}/${IMAGE_NAME}:pull" || true)"
  bare="$(curl -sS -o /dev/null -w '%{http_code}' --proto '=https' \
      -H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json" \
      "https://ghcr.io/v2/${OWNER}/${IMAGE_NAME}/manifests/latest" || true)"
  if [[ "${bare}" == "200" ]]; then
    rm -f "${body}"
    echo 200
    return 0
  fi
  # A private package refuses to issue an anonymous pull token.
  if [[ "${token_code}" == "401" ]]; then
    rm -f "${body}"
    echo 401
    return 0
  fi
  # DENIED, with no token, is what GHCR returns when the name is not a package.
  if [[ "${token_code}" == "403" ]]; then
    rm -f "${body}"
    echo 404
    return 0
  fi
  if [[ "${token_code}" != "200" ]]; then
    rm -f "${body}"
    echo unknown
    return 0
  fi
  tok="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("token",""))' "${body}" 2>/dev/null || true)"
  rm -f "${body}"
  if [[ -z "${tok}" ]]; then
    echo unknown
    return 0
  fi
  manifest="$(curl -sS -o /dev/null -w '%{http_code}' --proto '=https' \
      -H "Authorization: Bearer ${tok}" \
      -H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json" \
      "https://ghcr.io/v2/${OWNER}/${IMAGE_NAME}/manifests/latest" || true)"
  tags="$(curl -sS -o /dev/null -w '%{http_code}' --proto '=https' \
      -H "Authorization: Bearer ${tok}" \
      "https://ghcr.io/v2/${OWNER}/${IMAGE_NAME}/tags/list" || true)"
  if [[ "${manifest}" == "200" || "${tags}" == "200" ]]; then
    echo 200
    return 0
  fi
  if [[ "${manifest}" == "404" && "${tags}" == "404" ]]; then
    echo 404
    return 0
  fi
  echo 401
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
      if [[ "${GHCR_CREATE:-fail}" == "skip" ]]; then
        echo "ghcr-push-guard: ${IMAGE_NAME} does not exist and GHCR_PUBLISH_TOKEN is unset. Not creating it." >&2
        echo "::warning title=GHCR package not created::${IMAGE_NAME} is missing and GHCR_PUBLISH_TOKEN is unset. GITHUB_TOKEN will not create it." >&2
        echo skip
        return 0
      fi
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
  if [[ "$(GHCR_CREATE=skip decide 404 no)" != "skip" ]]; then
    echo "selftest FAIL iso skip" >&2
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
