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
# Only the container-embed recipe. The shared chroot() also runs the
# post hook; a mount there would make `rm` hit a live read-only file.
anchor = (
    "    podman pull {{ container_image || image }}\n"
    "    dnf install -y fuse-overlayfs\"\n"
    "    chroot \"$CMD\"\n"
)
replacement = (
    "    REGISTRY_AUTH_FILE=/root/.config/containers/auth.json "
    "podman pull {{ container_image || image }}\n"
    "    dnf install -y fuse-overlayfs\"\n"
    "    mkdir -p \"{{ git_root/rootfs }}/root/.config/containers\"\n"
    "    touch \"{{ git_root/rootfs }}/root/.config/containers/auth.json\"\n"
    "    chroot \"$CMD\" --volume /var/tmp/unwoke-ghcr-auth.json:/root/.config/containers/auth.json:ro\n"
    "    rm -f \"{{ git_root/rootfs }}/root/.config/containers/auth.json\"\n"
    "    rmdir \"{{ git_root/rootfs }}/root/.config/containers\" 2>/dev/null || true\n"
)
if text.count(anchor) != 1:
    raise SystemExit("titanoboa-private-auth: container-pull anchor is not unique")
text = text.replace(anchor, replacement, 1)
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
    dnf install -y fuse-overlayfs"
    chroot "$CMD"
EOF
  patch_justfile "${tmp}"
  grep -F -q 'chroot "$CMD" --volume /var/tmp/unwoke-ghcr-auth.json:/root/.config/containers/auth.json:ro' "${tmp}"
  grep -F -q 'REGISTRY_AUTH_FILE=/root/.config/containers/auth.json podman pull' "${tmp}"
  if [[ "$(grep -c 'unwoke-ghcr-auth.json' "${tmp}")" -ne 1 ]]; then
    echo "selftest FAIL auth mount is not limited to the container pull" >&2
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
