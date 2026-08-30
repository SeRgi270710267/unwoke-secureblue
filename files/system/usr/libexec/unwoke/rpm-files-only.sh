#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Download + GPG-check + extract RPM *files*. Never rpm -i / dnf install
# into the image rpmdb (that malforms Origin Packages so USB wrap dies).
# shellcheck shell=bash

unwoke_rpm_fedora() {
  local f
  f="$(rpm --eval '%{fedora}' 2>/dev/null || true)"
  if [[ "${f}" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "${f}"
  else
    printf '%s\n' "${UNWOKE_RELEASEVER:-44}"
  fi
}

unwoke_rpm_extract() {
  local rpm="$1" dest="${2:-/}" tgz
  [[ -f "${rpm}" ]] || return 1
  mkdir -p "${dest}"
  if command -v rpm2cpio >/dev/null && command -v cpio >/dev/null; then
    rpm2cpio "${rpm}" | (cd "${dest}" && cpio -idm --quiet)
    return 0
  fi
  if command -v rpm2archive >/dev/null; then
    if rpm2archive -n "${rpm}" 2>/dev/null | tar -x -C "${dest}"; then
      return 0
    fi
    tgz="${rpm}.tgz"
    rm -f "${tgz}"
    rpm2archive "${rpm}"
    tar -xzf "${tgz}" -C "${dest}"
    rm -f "${tgz}"
    return 0
  fi
  echo "FAIL: need rpm2cpio+cpio or rpm2archive to extract ${rpm}" >&2
  return 1
}

unwoke_rpm_verify() {
  local rpm="$1" key="$2"
  local db
  db="$(mktemp -d)"
  rpm --initdb --dbpath "${db}"
  rpm --dbpath "${db}" --import "${key}"
  rpm --dbpath "${db}" -K "${rpm}"
  rm -rf "${db}"
}

# Newest NEVRA href in a yum/dnf repo (repomd + primary.xml.gz). Curl only —
# dnf5 --installroot download still opened the compose rpmdb and left Origin
# Packages malformed so USB wrap died (wrap 33311501669 after files-only Brave).
unwoke_yum_href() {
  local base="$1" pkg="$2"
  python3 - "$base" "$pkg" <<'PY'
import gzip, re, sys, urllib.request, xml.etree.ElementTree as ET

base, want = sys.argv[1].rstrip("/"), sys.argv[2]
repo_ns = "{http://linux.duke.edu/metadata/repo}"
common_ns = "{http://linux.duke.edu/metadata/common}"


def bits(s):
    return [int(x) if x.isdigit() else x for x in re.findall(r"\d+|[A-Za-z]+", s or "0")]


def verkey(epoch, ver, rel):
    return (int(epoch or 0), bits(ver), bits(rel))


req = urllib.request.Request(
    base + "/repodata/repomd.xml",
    headers={"User-Agent": "unwoke-secureblue"},
)
with urllib.request.urlopen(req, timeout=60) as fh:
    repomd = ET.fromstring(fh.read())
href = None
for data in repomd.findall(repo_ns + "data"):
    if data.get("type") == "primary":
        loc = data.find(repo_ns + "location")
        if loc is not None:
            href = loc.get("href")
if not href:
    raise SystemExit("no primary.xml in repomd")
req = urllib.request.Request(
    base + "/" + href,
    headers={"User-Agent": "unwoke-secureblue"},
)
with urllib.request.urlopen(req, timeout=120) as fh:
    raw = gzip.decompress(fh.read())
root = ET.fromstring(raw)
best = None
best_key = None
for pkg in root.findall(common_ns + "package"):
    name = pkg.find(common_ns + "name")
    if name is None or name.text != want:
        continue
    loc = pkg.find(common_ns + "location")
    ver = pkg.find(common_ns + "version")
    if loc is None or loc.get("href") is None:
        continue
    epoch = ver.get("epoch") if ver is not None else "0"
    version = ver.get("ver") if ver is not None else "0"
    rel = ver.get("rel") if ver is not None else "0"
    key = verkey(epoch, version, rel)
    if best_key is None or key > best_key:
        best_key = key
        best = loc.get("href")
if not best:
    raise SystemExit(f"package {want} not in {base}")
print(base + "/" + best)
PY
}

unwoke_yum_fetch() {
  local dest="$1" base="$2" pkg="$3" href fname
  [[ -n "${dest}" && -n "${base}" && -n "${pkg}" ]] || return 1
  mkdir -p "${dest}"
  href="$(unwoke_yum_href "${base}" "${pkg}")" || return 1
  fname="$(basename "${href}")"
  curl -fsSL --tlsv1.2 --retry 5 -o "${dest}/${fname}" "${href}"
}

# Download Fedora NEVRAs with curl. Never dnf5 — even --installroot download
# WAL-wrote the ostree sqlite on Origin compose.
unwoke_rpm_download() {
  local dest="$1"
  shift
  [[ "$#" -ge 1 ]] || return 1
  local fedora pkg href fname base got
  fedora="$(unwoke_rpm_fedora)"
  mkdir -p "${dest}"
  for pkg in "$@"; do
    got=0
    for base in \
      "https://dl.fedoraproject.org/pub/fedora/linux/updates/${fedora}/Everything/x86_64" \
      "https://download.fedoraproject.org/pub/fedora/linux/updates/${fedora}/Everything/x86_64" \
      "https://dl.fedoraproject.org/pub/fedora/linux/releases/${fedora}/Everything/x86_64/os" \
      "https://download.fedoraproject.org/pub/fedora/linux/releases/${fedora}/Everything/x86_64/os"
    do
      if href="$(unwoke_yum_href "${base}" "${pkg}" 2>/dev/null)"; then
        fname="$(basename "${href}")"
        if curl -fsSL --tlsv1.2 --retry 5 -o "${dest}/${fname}" "${href}"; then
          got=1
          break
        fi
      fi
    done
    [[ "${got}" -eq 1 ]] || {
      echo "FAIL: curl did not fetch ${pkg} from Fedora ${fedora}" >&2
      return 1
    }
  done
}
