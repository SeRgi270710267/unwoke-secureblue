# Unwoke SecureBlue

**secureblue’s hardening. Brave Origin *or* no browser. Terminal, no curator store.**

The product name is **Unwoke SecureBlue**. Git and GHCR stay lowercase (`unwoke-secureblue`, `unwoke-silverblue`) because registries and rebase commands are slugs, not titles.

This is a daily overlay on official [secureblue](https://secureblue.dev) images. It is **not** a fork and **not** affiliated with them. Their kernel hardening, `hardened_malloc`, SELinux, no Xwayland by default, and automatic updates stay. We only strip the two product decisions that lock the desktop: **Trivalent** and **Bazaar**. No GUI software store is added back. Two flavors: **Brave Origin**, or **browserless** (no Trivalent, no Origin, no `brave_t`).

Site: [sergi270710267.github.io/unwoke-secureblue](https://sergi270710267.github.io/unwoke-secureblue/)

Images: `ghcr.io/sergi270710267/unwoke-silverblue` · `unwoke-kinoite` · `*-nvidia-open` · `*-browserless`

---

## Why this exists (receipts, not vibes)

Stock secureblue is a serious hardened Fedora Atomic. It also ships a house browser and a house app store that decide what you may install.

| | Stock [secureblue](https://secureblue.dev) | Origin images | Browserless images (`*-browserless`) |
| --- | --- | --- | --- |
| Browser | [Trivalent](https://github.com/secureblue/Trivalent) — their Chromium, default, SELinux-confined | **[Brave Origin](https://brave.com/origin/linux/)** standalone RPM (`brave-origin`). Default browser. Runs in `brave_t`. | **None.** No Trivalent, no Origin. `harden_userns` is stock (Flatpak only). |
| App store | [Bazaar](https://github.com/secureblue/bazaar-rpm) — curated catalog | **None.** Flathub remote is added for `flatpak` CLI. | **None.** Flathub is **not** added. Use `brew` / `rpm-ostree`. |
| User namespaces | Off for unconfined; on for Flatpak and Trivalent | Same, plus `brave_t` on their userns allow-list so Origin’s sandbox can start | Same as stock with Trivalent gone: unconfined blocked, Flatpak allowed, no extra domain |

`brave_t` (Origin images only) is an unconfined-like domain so Brave Origin can run. It is **not** Trivalent’s tight confinement. Browserless does not load it.

Browserless is safer than Origin **until you install a browser**. Easy host installs are blocked until `ujust set-allow-browsers on ALLOW` (Flatpak mask + rpm-ostree exclude). That is a seatbelt: toolbox, brew, AppImage, and `rpm-ostree --disableexcludes` still work. It is not a Trivalent replacement.

What we *can* do on Brave Origin is force Chromium enterprise policies and keep their `ujust` surface. Stock commands still work (`ujust set-unconfined-userns`, `ujust set-kargs-hardening`, `ujust audit-secureblue`, …). Overlay extras:

```bash
ujust unwoke-status
ujust audit-unwoke
ujust set-brave-hardening on    # Origin images. Restart Brave Origin.
ujust set-brave-jitless on      # Origin images; breaks some sites.
ujust set-allow-browsers on ALLOW   # browserless only; unlocks Flatpak/rpm-ostree browsers
ujust set-allow-browsers off
```

We did **not** gut SELinux, kernel args, `hardened_malloc`, disk encryption, or Secure Boot enrollment. Calling this “insecure Fedora” is false. Calling it “identical to secureblue” is also false.

---

## Images (rebuilt every day, 08:00 UTC)

| Image | Desktop | GPU | Browser |
| --- | --- | --- | --- |
| `unwoke-silverblue` | GNOME | Nouveau | Brave Origin |
| `unwoke-silverblue-nvidia-open` | GNOME | NVIDIA open (GTX 16xx / RTX+) | Brave Origin |
| `unwoke-kinoite` | KDE Plasma | Nouveau | Brave Origin |
| `unwoke-kinoite-nvidia-open` | KDE Plasma | NVIDIA open (GTX 16xx / RTX+) | Brave Origin |
| `unwoke-silverblue-browserless` | GNOME | Nouveau | none |
| `unwoke-silverblue-nvidia-open-browserless` | GNOME | NVIDIA open | none |
| `unwoke-kinoite-browserless` | KDE Plasma | Nouveau | none |
| `unwoke-kinoite-nvidia-open-browserless` | KDE Plasma | NVIDIA open | none |

Published as `ghcr.io/sergi270710267/<name>:latest`. All are **public**. No GitHub login to pull.

---

## Install (one command)

Already on secureblue (or any Fedora Atomic):

```bash
rpm-ostree rebase ostree-unverified-registry:ghcr.io/sergi270710267/unwoke-silverblue:latest
systemctl reboot
```

That first switch **cannot** check our stamp yet (your PC does not have our key). After that reboot, a first-boot service **queues the signed image**. Reboot **one more time** when `rpm-ostree status` shows a staged signed deployment (or after a few minutes on the network). From then on, updates must match our `cosign.pub`.

If it did not auto-stage (no network on first boot), do it yourself:

```bash
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/sergi270710267/unwoke-silverblue:latest
systemctl reboot
```

Empty disk: flash a [secureblue ISO](https://secureblue.dev/install) first (encrypt, wheel, enroll their Secure Boot key), then the commands above.

KDE → `unwoke-kinoite`. NVIDIA → add `-nvidia-open`. No browser → add `-browserless` (e.g. `unwoke-silverblue-browserless`).

```bash
cosign verify --key cosign.pub ghcr.io/sergi270710267/unwoke-silverblue
```

---

## USB ISO

The OS **is** the GHCR image. A flashable ISO is optional.

Actions → **iso** → Run workflow → pick the image → download the artifact (kept 14 days). GitHub will not host a 3 GB ISO as a normal release.

---

## How it stays current (and how the signatures work)

Not a git fork of `secureblue/secureblue`. Forks rot. We pull their **already-built, already-signed** images.

```yaml
base-image: ghcr.io/secureblue/silverblue-main-hardened
image-version: latest
```

**Trust chain**

1. secureblue builds and **cosign-signs** `ghcr.io/secureblue/…-hardened`.
2. Our CI downloads [their public key](https://github.com/secureblue/secureblue/blob/live/cosign.pub), checks it still matches `keys/secureblue.pub` in this repo, **`cosign verify`s the base**, then **pins that digest** so `:latest` cannot swap mid-build.
3. We drop Trivalent+Bazaar+GUI stores+full `brave-browser`. Origin images then layer **Brave Origin** (`brave-origin`) and a `brave_t` SELinux domain. Browserless images skip that. Then we **cosign-sign our image** with `cosign.pub` in this repo.
4. Your PC pulls `ghcr.io/sergi270710267/unwoke-…` and, after the signed rebase, verifies **our** signature.

That is as close as an overlay gets to “updating from their source” without merging their git. We do **not** rebuild their kernel or re-run their SLSA pipeline; we inherit whatever they already shipped, after checking their signature.

Rebuilds: **08:00 and 20:00 UTC**, plus every recipe push.

Factory extras (this repo, not the desktop):

- **Harden-Runner** on CI (audit outbound traffic)
- GitHub Actions **pinned to commit SHAs**
- **SLSA-style provenance** attached to each published image (`attest-build-provenance`)
- BlueBuild CLI install is **signature-checked**

We do **not** use a hardware signing key. `cosign.key` lives only as the GitHub secret `SIGNING_SECRET`. A YubiKey would be stricter; it is not wired up.

Your machine then follows this repo with normal `rpm-ostree` updates.

| Change | File |
| --- | --- |
| Packages | `recipes/common.yml` |
| Browser / first-boot | `files/scripts/apply-unwoke.sh` |
| Brave SELinux / userns | `files/scripts/install-brave-selinux.sh`, `files/system/usr/share/unwoke/selinux/` |
| ujust extras | `files/justfiles/unwoke.just`, `files/system/usr/libexec/unwoke/toggles.sh` |
| GNOME favorites | `files/gschema-overrides/zz2-unwoke.gschema.override` |

---

## License

Overlay files: MIT. Fedora, secureblue, BlueBuild, Brave, Trivalent: their licenses. Unaffiliated with secureblue.
