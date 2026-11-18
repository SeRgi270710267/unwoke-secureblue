#!/usr/bin/env bash
# Titanoboa's rootfs-include-container runs podman pull inside the live
# rootfs. That pull cannot see the host login. Mount a host auth file
# read-only and point REGISTRY_AUTH_FILE at it. The mount is not copied
# into the ISO. Do not print the auth file.
#
#   titanoboa-private-auth.sh path/to/Justfile
#   titanoboa-private-auth.sh --selftest
set -euo pipefail

patch_justfile() {
  local justfile="$1"
  python3 - "${justfile}" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
volume = (
    "    --volume ' + git_root + ':/app \\\n"
    "    --rootfs ' + git_root/rootfs + ' \\\n"
)
mount = (
    "    --volume ' + git_root + ':/app \\\n"
    "    --volume /var/tmp/unwoke-ghcr-auth.json:/root/.config/containers/auth.json:ro \\\n"
    "    --rootfs ' + git_root/rootfs + ' \\\n"
)
pull = "    podman pull {{ container_image || image }}\n"
authed = (
    "    REGISTRY_AUTH_FILE=/root/.config/containers/auth.json "
    "podman pull {{ container_image || image }}\n"
)
if volume not in text:
    raise SystemExit("titanoboa-private-auth: chroot volume anchor missing")
if pull not in text:
    raise SystemExit("titanoboa-private-auth: podman pull anchor missing")
if text.count(volume) != 1 or text.count(pull) != 1:
    raise SystemExit("titanoboa-private-auth: anchor is not unique")
text = text.replace(volume, mount, 1).replace(pull, authed, 1)
path.write_text(text, encoding="utf-8")
PY
}

selftest() {
  local tmp
  tmp="$(mktemp)"
  cat > "${tmp}" <<'EOF'
    --volume ' + git_root + ':/app \
    --rootfs ' + git_root/rootfs + ' \
    podman pull {{ container_image || image }}
EOF
  patch_justfile "${tmp}"
  grep -q 'unwoke-ghcr-auth.json:/root/.config/containers/auth.json:ro' "${tmp}"
  grep -q 'REGISTRY_AUTH_FILE=/root/.config/containers/auth.json podman pull' "${tmp}"
  if grep -c 'podman pull' "${tmp}" | grep -qx 1; then
    :
  else
    echo "selftest FAIL pull count" >&2
    rm -f "${tmp}"
    return 1
  fi
  rm -f "${tmp}"
  echo "titanoboa-private-auth selftest ok"
}

if [[ "${1:-}" == "--selftest" ]]; then
  selftest
  exit 0
fi

justfile="${1:?usage: titanoboa-private-auth.sh Justfile}"
[[ -f "${justfile}" ]] || { echo "titanoboa-private-auth: missing ${justfile}" >&2; exit 1; }
patch_justfile "${justfile}"
echo "titanoboa-private-auth: chroot pull uses the host auth file"
