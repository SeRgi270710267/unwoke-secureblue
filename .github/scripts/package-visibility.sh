#!/usr/bin/env bash
# Report whether Unwoke GHCR packages are still anonymously pullable.
# Never changes visibility. A public package cannot be made private again;
# the owner deletes it and the next bake creates a private one.
set -u

OWNER="${GITHUB_REPOSITORY_OWNER:-sergi270710267}"
OWNER="${OWNER,,}"
ROOT="${GITHUB_WORKSPACE:-.}"
NAMES_FILE="${ROOT}/.github/scripts/package-names.txt"

if [[ ! -f "${NAMES_FILE}" ]]; then
  echo "package-visibility: missing ${NAMES_FILE}" >&2
  exit 0
fi

mapfile -t base_names < <(grep -E '^unwoke-[a-z0-9-]+$' "${NAMES_FILE}" || true)

declare -A seen=()
queue=()
for n in "${base_names[@]}"; do
  seen["${n}"]=1
  queue+=("${n}")
done

if command -v gh >/dev/null && [[ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]]; then
  export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN}}"
  listed="$(gh api --paginate "users/${OWNER}/packages?package_type=container&per_page=100" \
    --jq '.[].name' 2>/dev/null || true)"
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
fi

# Anonymous token, then manifest. 200 means the world can still pull.
# Do not print the bearer.
anon_state() {
  local name="$1"
  local tok code
  tok="$(curl -fsSL --retry 3 --retry-delay 1 --proto '=https' \
      "https://ghcr.io/token?service=ghcr.io&scope=repository:${OWNER}/${name}:pull" \
      | python3 -c 'import json,sys; print(json.load(sys.stdin).get("token",""))' \
      2>/dev/null || true)"
  if [[ -z "${tok}" ]]; then
    echo unknown
    return 0
  fi
  code="$(curl -sS -o /dev/null -w '%{http_code}' --proto '=https' \
      -H "Authorization: Bearer ${tok}" \
      -H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json" \
      "https://ghcr.io/v2/${OWNER}/${name}/manifests/latest" || true)"
  case "${code}" in
    200) echo public ;;
    401|403|404) echo closed ;;
    *) echo unknown ;;
  esac
}

public_names=()
unknown_names=()
echo "package-visibility: owner=${OWNER} (this script does not change visibility)"
for n in "${queue[@]}"; do
  state="$(anon_state "${n}")"
  echo "${state}  ${n}"
  case "${state}" in
    public) public_names+=("${n}") ;;
    unknown) unknown_names+=("${n}") ;;
  esac
done

echo "package-visibility: public=${#public_names[@]} unknown=${#unknown_names[@]}"
echo "package-visibility: anonymous 401 is not proof inherit is off. A private package that inherits this public repository can still be pulled by any GitHub user."
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "public_count=${#public_names[@]}" >> "${GITHUB_OUTPUT}"
fi

if [[ "${ALARM:-}" != "1" ]]; then
  exit 0
fi
alarm="${ROOT}/.github/scripts/issue-alarm.sh"
if [[ ! -f "${alarm}" ]]; then
  exit 0
fi
if [[ "${#public_names[@]}" -gt 0 ]]; then
  extra="Anonymous pull still returns 200:"
  for n in "${public_names[@]}"; do
    extra="${extra}
- \`${n}\`"
  done
  extra="${extra}

GitHub does not let a public package be made private again. Delete the package after the repository is private, then let the bake create a new private one. Do not click Public. Steps: invite/OWNER-STEPS.md."
  ALARM_EXTRA="${extra}" bash "${alarm}" packages open || true
elif [[ "${#unknown_names[@]}" -eq 0 ]]; then
  bash "${alarm}" packages close || true
else
  echo "package-visibility: inconclusive; leaving the alarm as it is"
fi
exit 0
