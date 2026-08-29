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

set_public() {
  local name="$1"
  local vis
  vis="$(gh api "users/${OWNER}/packages/container/${name}" --jq .visibility 2>/dev/null || echo missing)"
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
  echo "WARN: still private: https://github.com/users/${OWNER}/packages/container/${name}/settings"
  echo "      GitHub → Packages → ${name} → Change visibility → Public (one click, then this job is a no-op)"
  still_private=$((still_private + 1))
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
    bash "${ROOT}/.github/scripts/issue-alarm.sh" packages open || true
  else
    bash "${ROOT}/.github/scripts/issue-alarm.sh" packages close || true
  fi
fi
exit 0
