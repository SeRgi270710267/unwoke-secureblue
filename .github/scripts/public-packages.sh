#!/usr/bin/env bash
# Best-effort: make Unwoke GHCR packages public so anonymous rebase works.
# First GHCR push is often private. Must not fail the overlay bake.
set -u

OWNER="${GITHUB_REPOSITORY_OWNER:-sergi270710267}"
OWNER="${OWNER,,}"

if ! command -v gh >/dev/null; then
  echo "public-packages: gh missing; skip"
  exit 0
fi
if [[ -z "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]]; then
  echo "public-packages: no token; skip"
  exit 0
fi
export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN}}"

NAMES=(
  unwoke-silverblue
  unwoke-silverblue-nvidia-open
  unwoke-kinoite
  unwoke-kinoite-nvidia-open
  unwoke-silverblue-browserless
  unwoke-silverblue-nvidia-open-browserless
  unwoke-kinoite-browserless
  unwoke-kinoite-nvidia-open-browserless
  unwoke-silverblue-trivalent
  unwoke-silverblue-nvidia-open-trivalent
  unwoke-kinoite-trivalent
  unwoke-kinoite-nvidia-open-trivalent
)

# Also cover USB ISO wraps if they exist.
iso_names=()
for n in "${NAMES[@]}"; do
  iso_names+=("${n}-iso")
done

listed=""
listed="$(gh api --paginate "users/${OWNER}/packages?package_type=container&per_page=100" \
  --jq '.[].name' 2>/dev/null || true)"

declare -A seen=()
queue=()
for n in "${NAMES[@]}" "${iso_names[@]}"; do
  seen["${n}"]=1
  queue+=("${n}")
done
if [[ -n "${listed}" ]]; then
  while IFS= read -r extra; do
    [[ -n "${extra}" ]] || continue
    case "${extra}" in
      unwoke-*)
        if [[ -z "${seen[${extra}]+x}" ]]; then
          seen["${extra}"]=1
          queue+=("${extra}")
        fi
        ;;
    esac
  done <<<"${listed}"
fi

still_private=0
private_names=()

# GITHUB_TOKEN often cannot PATCH visibility. Anonymous OCI pull is the
# rebase/USB truth: 200 = public even if the Packages API still says private.
anon_pull_ok() {
  local name="$1"
  local tok code
  tok="$(curl -fsSL --retry 3 --retry-delay 1 \
      "https://ghcr.io/token?service=ghcr.io&scope=repository:${OWNER}/${name}:pull" \
      | python3 -c 'import json,sys; print(json.load(sys.stdin).get("token",""))' \
      2>/dev/null || true)"
  [[ -n "${tok}" ]] || return 1
  code="$(curl -sS -o /dev/null -w '%{http_code}' \
      -H "Authorization: Bearer ${tok}" \
      -H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json" \
      "https://ghcr.io/v2/${OWNER}/${name}/manifests/latest" || true)"
  [[ "${code}" == "200" ]]
}

set_public() {
  local name="$1"
  local vis settings
  vis="$(gh api "users/${OWNER}/packages/container/${name}" --jq .visibility 2>/dev/null || echo missing)"
  settings="https://github.com/users/${OWNER}/packages/container/${name}/settings"
  case "${vis}" in
    public)
      echo "public  ${name}"
      return 0
      ;;
    missing)
      echo "absent  ${name}"
      return 0
      ;;
  esac
  if anon_pull_ok "${name}"; then
    echo "public  ${name} (anonymous pull; Packages API still ${vis})"
    return 0
  fi
  echo "private ${name} — trying to publish"
  if gh api --method PATCH \
      -H "Accept: application/vnd.github.package-deletes-preview+json" \
      "users/${OWNER}/packages/container/${name}" \
      -f visibility=public >/dev/null 2>&1; then
    echo "now public ${name}"
    return 0
  fi
  if gh api --method PUT \
      "users/${OWNER}/packages/container/${name}/visibility" \
      -f visibility=public >/dev/null 2>&1; then
    echo "now public ${name}"
    return 0
  fi
  if anon_pull_ok "${name}"; then
    echo "now public ${name} (anonymous pull)"
    return 0
  fi
  echo "WARN: still private: ${settings}"
  echo "      GitHub → Packages → ${name} → Change visibility → Public (one click, then this job is a no-op)"
  still_private=$((still_private + 1))
  private_names+=("${name}")
  return 0
}

echo "public-packages: owner=${OWNER}"
for n in "${queue[@]}"; do
  set_public "${n}"
done
echo "public-packages: still_private=${still_private} (warnings are not a failed bake)"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "still_private=${still_private}" >> "${GITHUB_OUTPUT}"
fi

ROOT="${GITHUB_WORKSPACE:-.}"
if [[ "${ALARM:-}" == "1" && -f "${ROOT}/.github/scripts/issue-alarm.sh" ]]; then
  if [[ "${still_private}" -gt 0 ]]; then
    extra="Still private after the factory tried Public:"
    for n in "${private_names[@]}"; do
      extra="${extra}
- \`${n}\` → https://github.com/users/${OWNER}/packages/container/${n}/settings"
    done
    extra="${extra}

Anonymous rebase of the twelve OS images can already work. The usual leftover is a first \`*-iso\` USB wrap. One Public click on each URL. Do not bump titanoboa or switch registry."
    ALARM_EXTRA="${extra}" bash "${ROOT}/.github/scripts/issue-alarm.sh" packages open || true
  else
    bash "${ROOT}/.github/scripts/issue-alarm.sh" packages close || true
  fi
fi
exit 0
