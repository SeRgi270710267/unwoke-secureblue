#!/usr/bin/env bash
# Unwoke SecureBlue. Not affiliated with Whonix or secureblue.
# MIT License. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
# Official Whonix KVM (not VirtualBox, not Qubes). OpenPGP-required.
# qemu:///session. Clipboard/USB/mic off. Their Internal/External nets.
set -euo pipefail

PIN="/usr/share/unwoke/whonix-kvm.json"
URI="qemu:///session"
WORKDIR="${XDG_CACHE_HOME:-$HOME/.cache}/unwoke-whonix"
IMGDIR="${XDG_DATA_HOME:-$HOME/.local/share}/images"
GNUPGHOME_W="${WORKDIR}/gnupg"

ask() {
  local prompt="$1" def="${2:-N}"
  local ans=""
  read -r -p "${prompt} [${def}] " ans || true
  ans="${ans:-$def}"
  [[ "${ans}" == [yY] ]]
}

jget() {
  python3 - "$PIN" "$1" <<'PY'
import json, sys
d = json.loads(open(sys.argv[1], encoding="utf-8").read())
v = d.get(sys.argv[2])
if isinstance(v, list):
    print("\n".join(str(x) for x in v))
elif v is not None:
    print(v)
PY
}

echo
echo "=== Whonix on Unwoke (KVM, official images) ==="
echo "Not Tails. Not Qubes. Two VMs: Gateway (Tor) + Workstation (no real IP)."
echo "We do not bake their disks. We download, OpenPGP-verify, import THEIR xml,"
echo "then turn off clipboard, USB passthrough, and mic (identity leaks)."
echo "Host stays Unwoke clearnet (updates, NTS). Do not put a VPN kill-switch"
echo "on the host while these VMs run — it breaks the Gateway."
echo "VirtualBox is not offered."
echo
echo "Pinned: $(jget version)  fingerprint $(jget fingerprint)"
echo "Docs: $(jget docs)"
echo

if ! grep -qE 'vmx|svm' /proc/cpuinfo 2>/dev/null; then
  echo "FAIL: CPU has no VMX/SVM. Whonix KVM needs that." >&2
  exit 1
fi

if ! ask "I have read Whonix limitations (metadata still exists; host compromise still sees you). Install?" "n"; then
  echo "Aborted."
  exit 0
fi
echo "License: $(jget license)"
if ! ask "Accept Whonix binary license / ToS (required to unpack)?" "n"; then
  echo "Aborted."
  exit 0
fi

echo
echo "Leftover stock: libvirt daemons. Needed to run VMs."
if ask "Turn stock libvirt daemons on?" "y"; then
  ujust set-libvirt-daemons on || true
fi

need_layer=0
for p in qemu-kvm libvirt-client virt-manager virt-viewer xz gnupg2; do
  if ! rpm -q "$p" >/dev/null 2>&1 && ! command -v "${p%%-*}" >/dev/null 2>&1; then
    need_layer=1
  fi
done
if [[ "${need_layer}" -eq 1 ]]; then
  echo "Layer Fedora KVM stack (rpm-ostree). Reboot, then run ujust install-whonix again."
  if ask "rpm-ostree install qemu-kvm libvirt virt-manager virt-viewer xz gnupg2 now?" "y"; then
    pkgs="$(jget packages | tr '\n' ' ') gnupg2"
    if [[ "$(id -u)" -eq 0 ]]; then
      # shellcheck disable=SC2086
      rpm-ostree install ${pkgs} || rpm-ostree install qemu-kvm libvirt-client virt-manager virt-viewer xz gnupg2
    else
      # shellcheck disable=SC2086
      run0 rpm-ostree install ${pkgs} || run0 rpm-ostree install qemu-kvm libvirt-client virt-manager virt-viewer xz gnupg2
    fi
    # shellcheck source=/usr/libexec/unwoke/continue-ostree.sh
    source /usr/libexec/unwoke/continue-ostree.sh
    unwoke_write_continue whonix
    echo "Reboot. Next login opens this wizard again. Or: ujust install-whonix"
    exit 0
  fi
fi

# shellcheck source=/usr/libexec/unwoke/continue-ostree.sh
source /usr/libexec/unwoke/continue-ostree.sh
unwoke_clear_continue

command -v gpg >/dev/null || { echo "FAIL: gpg missing" >&2; exit 1; }
command -v virsh >/dev/null || { echo "FAIL: virsh missing — layer KVM then reboot" >&2; exit 1; }
command -v curl >/dev/null || { echo "FAIL: curl missing" >&2; exit 1; }

mkdir -p "${WORKDIR}" "${IMGDIR}" "${GNUPGHOME_W}"
chmod 700 "${GNUPGHOME_W}"
export GNUPGHOME="${GNUPGHOME_W}"

key_url="$(jget key_url)"
fp="$(jget fingerprint | tr -d '[:space:]')"
curl --fail --location --proto '=https' --tlsv1.2 --max-time 120 \
  -o "${WORKDIR}/derivative.asc" "${key_url}"
got="$(gpg --batch --with-colons --import-options show-only --import "${WORKDIR}/derivative.asc" 2>/dev/null | awk -F: '/^fpr:/{print $10; exit}')"
if [[ "${got}" != "${fp}" ]]; then
  echo "FAIL: signing key fingerprint ${got:-empty} != pinned ${fp}" >&2
  exit 1
fi
gpg --batch --import "${WORKDIR}/derivative.asc" >/dev/null
echo "${fp}:6:" | gpg --batch --import-ownertrust >/dev/null 2>&1 || true
echo "OpenPGP key matches pinned fingerprint."

arch="$(jget archive_url)"
sig="$(jget sig_url)"
base="$(basename "${arch}")"
curl --fail --location --proto '=https' --tlsv1.2 \
  -o "${WORKDIR}/${base}.asc" "${sig}"
echo "Downloading $(jget version) (large). Keep this terminal open."
curl --fail --location --proto '=https' --tlsv1.2 \
  -o "${WORKDIR}/${base}" "${arch}"
if ! gpg --batch --verify-options show-notations --verify "${WORKDIR}/${base}.asc" "${WORKDIR}/${base}"; then
  echo "FAIL: OpenPGP signature. Do not unpack." >&2
  exit 1
fi
echo "Signature GOOD."

stage="${WORKDIR}/extract"
rm -rf "${stage}"
mkdir -p "${stage}"
tar -xSvf "${WORKDIR}/${base}" -C "${stage}"

# qemu session: skip raising RLIMIT_CORE
mkdir -p "${HOME}/.config/libvirt"
cat > "${HOME}/.config/libvirt/qemu.conf" <<'EOF'
# UNWOKE-SHIPPED-FIRST. Whonix KVM session (wiki).
max_core = 0
max_processes = 0
max_files = 0
EOF

export LIBVIRT_DEFAULT_URI="${URI}"

python3 - "${stage}" <<'PY'
import pathlib, sys, xml.etree.ElementTree as ET
root = pathlib.Path(sys.argv[1])

def harden(p: pathlib.Path) -> None:
    tree = ET.parse(p)
    r = tree.getroot()
    ns = ""
    if r.tag.startswith("{"):
        ns = r.tag.split("}")[0] + "}"
    dev = r.find(f"{ns}devices")
    if dev is None:
        return
    for g in list(dev):
        tag = g.tag.split("}")[-1]
        if tag == "hostdev" and g.get("type") == "usb":
            dev.remove(g)
        elif tag == "redirdev":
            dev.remove(g)
        elif tag == "audio":
            g.set("type", "none")
        elif tag == "sound":
            dev.remove(g)
        elif tag == "graphics":
            clip = g.find(f"{ns}clipboard")
            if clip is None:
                clip = ET.SubElement(g, f"{ns}clipboard" if ns else "clipboard")
            clip.set("copypaste", "no")
            # spice usbredir off
            for child in list(g):
                if child.tag.split("}")[-1] == "listen":
                    pass
    tree.write(p, encoding="utf-8", xml_declaration=True)

for xmlp in root.glob("Whonix-*.xml"):
    if "network" in xmlp.name.lower():
        continue
    harden(xmlp)
    print("hardened", xmlp.name)
PY

shopt -s nullglob
for nxml in "${stage}"/Whonix_*network*.xml "${stage}"/Whonix-*.xml; do
  [[ -f "${nxml}" ]] || continue
  if grep -qi network "${nxml}" && grep -qi '<network' "${nxml}"; then
    virsh -c "${URI}" net-define "${nxml}" >/dev/null 2>&1 || true
  fi
done
for n in Whonix-External Whonix-Internal; do
  virsh -c "${URI}" net-autostart "$n" >/dev/null 2>&1 || true
  virsh -c "${URI}" net-start "$n" >/dev/null 2>&1 || true
done

mkdir -p "${IMGDIR}"
gw_q=("${stage}"/Whonix-Gateway*.qcow2)
ws_q=("${stage}"/Whonix-Workstation*.qcow2)
[[ -f "${gw_q[0]}" && -f "${ws_q[0]}" ]] || { echo "FAIL: qcow2 missing in archive" >&2; exit 1; }
cp --sparse=always "${gw_q[0]}" "${IMGDIR}/Whonix-Gateway.qcow2"
cp --sparse=always "${ws_q[0]}" "${IMGDIR}/Whonix-Workstation.qcow2"

# Point XML at session image dir if needed
python3 - "${stage}" "${IMGDIR}" <<'PY'
import pathlib, sys, xml.etree.ElementTree as ET
stage, img = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
for name, dest in (("Gateway", img / "Whonix-Gateway.qcow2"), ("Workstation", img / "Whonix-Workstation.qcow2")):
    matches = list(stage.glob(f"Whonix-{name}*.xml"))
    if not matches:
        continue
    p = matches[0]
    tree = ET.parse(p)
    r = tree.getroot()
    for src in r.iter():
        if src.tag.split("}")[-1] == "source" and "file" in src.attrib:
            if src.attrib["file"].endswith(".qcow2"):
                src.set("file", str(dest))
    tree.write(p, encoding="utf-8", xml_declaration=True)
PY

gw_x=("${stage}"/Whonix-Gateway*.xml)
ws_x=("${stage}"/Whonix-Workstation*.xml)
virsh -c "${URI}" define "${gw_x[0]}"
virsh -c "${URI}" define "${ws_x[0]}"

apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
mkdir -p "${apps}"
cat > "${apps}/unwoke-whonix.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Whonix (Unwoke)
Comment=Start Gateway then Workstation. Clipboard/USB/mic stay off.
Exec=/usr/libexec/unwoke/start-whonix.sh
Icon=security-high
Terminal=false
Categories=Network;Security;
EOF

echo
echo "Imported. Start: ujust start-whonix  (or the Whonix icon)."
echo "Gateway first, then Workstation. Tor Browser lives *inside* Workstation."
echo "Do not log into the same accounts on the Unwoke host."
echo "Not Qubes. Host compromise still sees you."
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/unwoke"
echo "$(jget version)" > "${XDG_CONFIG_HOME:-$HOME/.config}/unwoke/whonix-kvm.version"
echo "Tutorial: https://sergi270710267.github.io/unwoke-secureblue/tutorials/whonix/"
