#!/usr/bin/env bash
# Live/installer ISO rootfs only. Does not change published GHCR OS images.
# @IMAGE_REF@ is replaced by iso.yml before Titanoboa runs.
# SPDX-FileCopyrightText: Copyright 2024 Universal Blue
# SPDX-FileCopyrightText: Copyright 2026 The Secureblue Authors
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

IMAGE_TAG="latest"
IMAGE_REF="@IMAGE_REF@"
IMAGE_REF="${IMAGE_REF%%:latest}"

if [[ "${IMAGE_REF}" == "@IMAGE_REF@" || -z "${IMAGE_REF}" ]]; then
  echo "FAIL: ISO hook IMAGE_REF was not substituted" >&2
  exit 1
fi

sed -i '/^install squashfs /d' /usr/lib/modprobe.d/secureblue.conf 2>/dev/null || true

# Live session only: drop bulky fonts and leftover store bits; add Anaconda.
dnf remove -y google-noto-fonts-all homebrew bazaar 2>/dev/null || true
dnf reinstall -y polkit || true
dnf install -y anaconda-live firefox libblockdev-btrfs libblockdev-lvm libblockdev-dm

systemctl disable --global secureblue-flatpak-setup.service secureblue-flatpak-setup.timer podman-auto-update.timer flatpak-user-update.timer 2>/dev/null || true
systemctl disable rpm-ostreed-automatic.timer rpm-ostree-countme.service bootloader-update.service 2>/dev/null || true
# Do not run overlay first-boot / admin-split / setup window on the live USB.
systemctl disable unwoke-first-boot.service unwoke-admin-split-setup.service 2>/dev/null || true
rm -f /etc/xdg/autostart/unwoke-first-session.desktop \
  /usr/etc/xdg/autostart/unwoke-first-session.desktop || true

rm -f /usr/share/applications/org.mozilla.Firefox.desktop \
  /usr/share/applications/org.mozilla.firefox.desktop \
  /usr/share/applications/firefox.desktop \
  /usr/share/applications/firefox-wayland.desktop \
  /usr/share/applications/firefox-x11.desktop || true

sed -i '/^Prepend=/s/$/;liveinst.desktop/' /usr/share/kde-settings/kde-profile/default/xdg/kicker-extra-favoritesrc || true

install -d /usr/share/pki/containers
cat > /usr/share/pki/containers/unwoke.pub <<'EOF'
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEJl7Y7j0vTtY/073t1VmhAqTwAjNK
LKBolcsGi6+d/EyH0djdLvJds40BjembjAgt7E8xTP+Ssxjgjlndhs+dzg==
-----END PUBLIC KEY-----
EOF

python3 - "${IMAGE_REF}" <<'PY'
import json, os, sys

image_ref = sys.argv[1]
paths = [
    "/etc/containers/policy.json",
    "/usr/etc/containers/policy.json",
]
path = next((p for p in paths if os.path.isfile(p)), None)
if path is None:
    raise SystemExit("FAIL: no containers policy.json in live rootfs")

with open(path, encoding="utf-8") as f:
    policy = json.load(f)

keys = ["/usr/share/pki/containers/unwoke.pub"]
for folder in ("/usr/etc/pki/containers", "/etc/pki/containers", "/usr/share/pki/containers"):
    if not os.path.isdir(folder):
        continue
    for name in sorted(os.listdir(folder)):
        if name.endswith(".pub"):
            keys.append(os.path.join(folder, name))
# Unique, stable order.
seen = set()
key_paths = []
for k in keys:
    if k not in seen and os.path.isfile(k):
        seen.add(k)
        key_paths.append(k)

transports = policy.setdefault("transports", {})
storage = transports.setdefault("containers-storage", {})
storage[""] = [
    {
        "type": "sigstoreSigned",
        "keyPaths": key_paths,
        "signedIdentity": {
            "type": "exactRepository",
            "dockerRepository": image_ref,
        },
    }
]
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(policy, f, indent=2)
    f.write("\n")
os.replace(tmp, path)
print(f"live ISO containers-storage policy -> {image_ref}")
PY

cat > /usr/share/glib-2.0/schemas/zz3-unwoke-installer-power.gschema.override <<'EOF'
[org.gnome.settings-daemon.plugins.power]
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'
sleep-inactive-ac-timeout=0
sleep-inactive-battery-timeout=0

[org.gnome.desktop.session]
idle-delay=uint32 0
EOF

sed -i '/^UMASK[[:blank:]]/s/027/022/' /etc/login.defs || true
rm -f /etc/xdg/autostart/org.gnome.Software.desktop || true
echo 'DefaultDisabled=true' > /usr/share/gnome-shell/search-providers/org.gnome.Software-search-provider.ini || true

sed -i -e 's/ Fedora/ Unwoke SecureBlue/' /usr/share/anaconda/gnome/fedora-welcome || true
sed -i -e 's/Fedora/Unwoke SecureBlue/g' /usr/share/anaconda/gnome/org.fedoraproject.welcome-screen.desktop || true

mkdir -p /etc/anaconda/profile.d
cat > /etc/anaconda/profile.d/unwoke-secureblue.conf <<'EOF'
# Anaconda configuration file for Unwoke SecureBlue (live ISO only)

[Profile]
profile_id = unwoke-secureblue

[Profile Detection]
os_id = secureblue

[Network]
default_on_boot = FIRST_WIRED_WITH_LINK

[Bootloader]
efi_dir = fedora
menu_auto_hide = True

[Storage]
default_scheme = BTRFS
btrfs_compression = zstd:1
default_partitioning =
    /     (min 1 GiB, max 70 GiB)
    /home (min 500 MiB, free 50 GiB)
    /var  (btrfs)

[User Interface]
custom_stylesheet = /usr/share/anaconda/pixmaps/silverblue/fedora-silverblue.css
hidden_spokes =
    NetworkSpoke
    PasswordSpoke
hidden_webui_pages =
    root-password
    network
password_policies =
        root (quality 100, length 15)
        user (quality 50, length 8)
        luks (quality 100, length 15)
EOF

sbkey='https://github.com/secureblue/secureblue/raw/0d8f58d7c6482e97a620a336643fadff55dcd352/files/system/etc/pki/akmods/certs/akmods-secureblue.der'
curl --retry 15 -Lo /etc/sb_pubkey.der "${sbkey}"

mkdir -p /usr/share/anaconda/post-scripts
tee /usr/share/anaconda/post-scripts/secureboot-enroll-key.ks <<'EOF'
%post --erroronfail --nochroot
set -oue pipefail

readonly ENROLLMENT_PASSWORD="secureblue"
readonly SECUREBOOT_KEY="/etc/sb_pubkey.der"

if [[ ! -d "/sys/firmware/efi" ]]; then
    echo "EFI mode not detected. Skipping key enrollment."
    exit 0
fi

if [[ ! -f "$SECUREBOOT_KEY" ]]; then
    echo "Secure boot key not provided: $SECUREBOOT_KEY"
    exit 0
fi

if grep -Eq 'Jupiter|Galileo' /sys/devices/virtual/dmi/id/product_name; then
    echo "Steam Deck hardware detected. Skipping key enrollment."
    exit 0
fi

mokutil --timeout -1 || true
echo -e "$ENROLLMENT_PASSWORD\n$ENROLLMENT_PASSWORD" | mokutil --import "$SECUREBOOT_KEY" || true
%end
EOF

tee -a /usr/share/anaconda/interactive-defaults.ks <<EOF
ostreecontainer --url=${IMAGE_REF}:${IMAGE_TAG} --transport=containers-storage
%include /usr/share/anaconda/post-scripts/install-configure-upgrade.ks
%include /usr/share/anaconda/post-scripts/secureboot-enroll-key.ks
EOF

tee /usr/share/anaconda/post-scripts/install-configure-upgrade.ks <<EOF
%post --erroronfail
bootc switch --mutate-in-place --enforce-container-sigpolicy --transport registry ${IMAGE_REF}:${IMAGE_TAG}
%end
EOF

# Anaconda on the live USB needs Xwayland. Installed image keeps stock.
rm -f /etc/sway/config.d/99-noxwayland.conf \
  /etc/systemd/user/org.gnome.Shell@user.service.d/override.conf \
  /etc/systemd/user/plasma-kwin_wayland.service.d/override.conf || true
