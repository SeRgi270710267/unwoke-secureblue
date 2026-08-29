#!/usr/bin/env bash
# One GitHub Release tag "receipt": overlay pubkey + cosign-verified GHCR digests.
# Not the OS. Not the USB (over 2 GiB). Never fails the overlay bake.
# Lives under docs/_tools so editing it cannot start an overlay bake.
set -u

TAG="receipt"
ROOT="${GITHUB_WORKSPACE:-.}"
ALARM="${ROOT}/.github/scripts/issue-alarm.sh"
PUB="${ROOT}/cosign.pub"
OWNER="${GITHUB_REPOSITORY_OWNER:-sergi270710267}"
OWNER="${OWNER,,}"
RUN_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-SeRgi270710267/unwoke-secureblue}/actions/runs/${GITHUB_RUN_ID:-0}"

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

finish_ok() {
  if [[ -f "${ALARM}" ]]; then
    bash "${ALARM}" receipt close || true
  fi
  echo "receipt: ok"
  exit 0
}

finish_fail() {
  echo "receipt: FAIL: $*" >&2
  if [[ -f "${ALARM}" ]]; then
    ALARM_EXTRA="$*" bash "${ALARM}" receipt open || true
  fi
  exit 0
}

[[ -f "${PUB}" ]] || finish_fail "missing ${PUB}"
command -v gh >/dev/null || finish_fail "gh missing"
command -v cosign >/dev/null || finish_fail "cosign missing"
[[ -n "${GITHUB_REPOSITORY:-}" ]] || finish_fail "GITHUB_REPOSITORY unset"
[[ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]] || finish_fail "no token"
export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN}}"

bash "${ROOT}/.github/scripts/install-crane.sh" || finish_fail "crane install failed"
export PATH="${HOME}/.local/bin:${PATH}"
command -v crane >/dev/null || finish_fail "crane missing"

extra=()
if cosign verify --help 2>&1 | grep -q -- '--new-bundle-format'; then
  extra+=(--new-bundle-format=false)
fi

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
digests="${work}/DIGESTS.txt"
{
  echo "# Unwoke SecureBlue GHCR digests (cosign-verified with cosign.pub)."
  echo "# Not an OS image. Do not flash this file. Rebase from ghcr.io."
  echo "# Updated $(date -u +%Y-%m-%dT%H:%M:%SZ)  ${RUN_URL}"
  echo
} > "${digests}"

ok=0
missing=()
for name in "${NAMES[@]}"; do
  img="ghcr.io/${OWNER}/${name}:latest"
  digest="$(crane digest "${img}" 2>/dev/null || true)"
  if [[ -z "${digest}" ]]; then
    echo "receipt: no digest ${img}"
    missing+=("${name} (no digest)")
    continue
  fi
  payload="$(COSIGN_OCI_EXPERIMENTAL=0 cosign verify --key "${PUB}" "${extra[@]}" "${img}" 2>/dev/null || true)"
  if [[ -z "${payload}" ]]; then
    echo "receipt: no Unwoke signature ${img}"
    missing+=("${name} (no signature)")
    continue
  fi
  echo "${img}@${digest}" >> "${digests}"
  echo "receipt: ${name} ${digest}"
  ok=$((ok + 1))
done

if [[ "${ok}" -lt 1 ]]; then
  finish_fail "0/${#NAMES[@]} images verified; left the last good receipt alone"
fi

cp -f "${PUB}" "${work}/cosign.pub"
# Optional USB checksums (tiny). Never attach the ISO.
if [[ -d "${RECEIPT_SUMS_DIR:-}" ]]; then
  while IFS= read -r -d '' f; do
    bytes="$(wc -c < "${f}" | tr -d ' ')"
    [[ "${bytes}" -gt 0 && "${bytes}" -lt 1048576 ]] || continue
    base="$(basename "${f}")"
    parent="$(basename "$(dirname "${f}")")"
    parent="${parent#iso-checksums-}"
    out="${parent}.${base}"
    cp -f "${f}" "${work}/${out}"
    echo "receipt: attach ${out} (${bytes} bytes)"
  done < <(find "${RECEIPT_SUMS_DIR}" -type f \( -name 'SHA256SUMS' -o -name 'SHA256SUMS.sig' \) -print0 2>/dev/null)
fi

notes="${work}/NOTES.md"
{
  echo "Unwoke SecureBlue — current bake **receipt**."
  echo
  echo "This is **not** the operating system and **not** a USB image. GitHub Releases cap a file at 2 GiB; the ISO is ~4 GB. Ignore the source zip GitHub adds."
  echo
  echo "**Recommended:** \`unwoke-silverblue-trivalent\` (or kinoite / nvidia-open)."
  echo
  echo '```'
  echo "rpm-ostree rebase ostree-unverified-registry:ghcr.io/${OWNER}/unwoke-silverblue-trivalent:latest"
  echo "systemctl reboot"
  echo '```'
  echo
  echo "Then \`cosign verify --key cosign.pub ghcr.io/${OWNER}/unwoke-silverblue-trivalent\` (the \`cosign.pub\` attached here is the overlay key from this repo)."
  echo
  echo "- Images listed: **${ok}/${#NAMES[@]}** (cosign-verified)."
  echo "- Enroll **their** Secure Boot key. Not Ventoy. Not affiliated with secureblue."
  echo "- \`SHIPPED-FIRST.txt\` is the dated ledger of official tickets Unwoke shipped while they were still requests. Token \`UNWOKE-SHIPPED-FIRST\`."
  echo "- Updated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- Run: ${RUN_URL}"
  if [[ "${#missing[@]}" -gt 0 ]]; then
    echo
    echo "Not listed this round:"
    for m in "${missing[@]}"; do
      echo "- \`${m}\`"
    done
  fi
} > "${notes}"

if ! gh release view "${TAG}" --repo "${GITHUB_REPOSITORY}" >/dev/null 2>&1; then
  gh release create "${TAG}" \
    --repo "${GITHUB_REPOSITORY}" \
    --target "${GITHUB_SHA:-main}" \
    --title "Current bake receipt" \
    --notes-file "${notes}" \
    --latest \
    || finish_fail "could not create release ${TAG}"
else
  gh release edit "${TAG}" \
    --repo "${GITHUB_REPOSITORY}" \
    --title "Current bake receipt" \
    --notes-file "${notes}" \
    --latest \
    || finish_fail "could not edit release ${TAG}"
fi

ledger="${ROOT}/files/system/usr/share/unwoke/SHIPPED-FIRST.txt"
if [[ ! -f "${ledger}" ]]; then
  ledger="${ROOT}/docs/ahead/SHIPPED-FIRST.txt"
fi
if [[ -f "${ledger}" ]]; then
  cp -f "${ledger}" "${work}/SHIPPED-FIRST.txt"
fi

uploads=("${work}/cosign.pub" "${digests}")
if [[ -f "${work}/SHIPPED-FIRST.txt" ]]; then
  uploads+=("${work}/SHIPPED-FIRST.txt")
fi
shopt -s nullglob
for f in "${work}"/*.SHA256SUMS "${work}"/*.SHA256SUMS.sig; do
  uploads+=("${f}")
done
shopt -u nullglob

gh release upload "${TAG}" "${uploads[@]}" \
  --repo "${GITHUB_REPOSITORY}" \
  --clobber \
  || finish_fail "could not upload receipt assets"

if [[ "${#missing[@]}" -gt 0 ]]; then
  finish_fail "receipt published but ${#missing[@]} flavor(s) omitted: ${missing[*]}"
fi
finish_ok
