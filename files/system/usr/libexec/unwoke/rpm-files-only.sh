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

# Download NEVRA RPMs into dest using a throwaway installroot (no image rpmdb).
# Extra args after dest are passed to dnf5 download (package names / --repofrompath).
unwoke_rpm_download() {
  local dest="$1"
  shift
  [[ "$#" -ge 1 ]] || return 1
  local root fedora
  fedora="$(unwoke_rpm_fedora)"
  root="$(mktemp -d)"
  mkdir -p \
    "${root}/usr/lib/sysimage/rpm" \
    "${root}/etc/yum.repos.d" \
    "${root}/etc/dnf/vars" \
    "${root}/etc/pki/rpm-gpg" \
    "${root}/var/cache" \
    "${dest}"
  rpm --initdb --dbpath "${root}/usr/lib/sysimage/rpm"
  printf '%s\n' "${fedora}" > "${root}/etc/dnf/vars/releasever"
  # Fedora/updates only. Copying secureblue.repo into a throwaway
  # installroot dies on an interactive GPG prompt (bake fac79ef).
  for dir in /etc/yum.repos.d /usr/etc/yum.repos.d; do
    [[ -d "${dir}" ]] || continue
    for f in fedora.repo fedora-updates.repo fedora-cisco-openh264.repo; do
      [[ -f "${dir}/${f}" ]] && cp -a "${dir}/${f}" "${root}/etc/yum.repos.d/"
    done
  done
  if [[ -d /etc/pki/rpm-gpg ]]; then
    cp -a /etc/pki/rpm-gpg/. "${root}/etc/pki/rpm-gpg/" || true
  fi
  if [[ -f /etc/os-release ]]; then
    mkdir -p "${root}/etc"
    cp -a /etc/os-release "${root}/etc/os-release"
  fi
  dnf5 -y --installroot="${root}" --releasever="${fedora}" \
    --setopt=cachedir="${root}/var/cache/libdnf5" \
    --setopt=keepcache=True \
    --nogpgcheck \
    download --destdir="${dest}" "$@"
  rm -rf "${root}"
}
