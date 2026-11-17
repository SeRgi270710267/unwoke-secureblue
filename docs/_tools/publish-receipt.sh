#!/usr/bin/env bash
# Retire the public "receipt" release. It used to attach cosign.pub and
# GHCR digests. Those names stay on a public release after the packages
# are private, so this script deletes the release and its tag.
# It does not create a release, upload digests, or print image refs.
# Never fails the overlay bake.
set -u

TAG="receipt"
ROOT="${GITHUB_WORKSPACE:-.}"
ALARM="${ROOT}/.github/scripts/issue-alarm.sh"

finish_ok() {
  if [[ -f "${ALARM}" ]]; then
    bash "${ALARM}" receipt close || true
  fi
  echo "receipt: public release retired"
  exit 0
}

finish_fail() {
  echo "receipt: FAIL: $*" >&2
  if [[ -f "${ALARM}" ]]; then
    ALARM_EXTRA="$*

Delete it by hand: gh release delete ${TAG} --repo ${GITHUB_REPOSITORY:-} --cleanup-tag --yes
Do not upload DIGESTS or the ISO." bash "${ALARM}" receipt open || true
  fi
  exit 0
}

command -v gh >/dev/null || finish_fail "gh missing"
[[ -n "${GITHUB_REPOSITORY:-}" ]] || finish_fail "GITHUB_REPOSITORY unset"
[[ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]] || finish_fail "no token"
export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN}}"

if ! gh release view "${TAG}" --repo "${GITHUB_REPOSITORY}" >/dev/null 2>&1; then
  echo "receipt: no ${TAG} release"
  finish_ok
fi

if gh release delete "${TAG}" --repo "${GITHUB_REPOSITORY}" --cleanup-tag --yes; then
  finish_ok
fi
finish_fail "could not delete release ${TAG}. The ruleset may be holding the tag."
