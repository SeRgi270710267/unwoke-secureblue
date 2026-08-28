# unwoke-secureblue

**secureblue’s hardening. Your browser. Your store. No curator.**

This is a daily overlay on official [secureblue](https://secureblue.dev) images. It is **not** a fork and **not** affiliated with them. Their kernel hardening, `hardened_malloc`, SELinux, no Xwayland by default, and automatic updates stay. We only strip the two product decisions that lock the desktop: **Trivalent** and **Bazaar**.

Images: `ghcr.io/sergi270710267/unwoke-silverblue` · `unwoke-kinoite` · `*-nvidia-open`

---

## Why this exists (receipts, not vibes)

Stock secureblue is a serious hardened Fedora Atomic. It also ships a house browser and a house app store that decide what you may install.

| | Stock [secureblue](https://secureblue.dev) | This overlay |
| --- | --- | --- |
| Browser | [Trivalent](https://github.com/secureblue/Trivalent) — their Chromium, default, SELinux-confined | **Official Brave RPM** from [brave.com/linux](https://brave.com/linux/) (`brave-browser` 1.94+ in the last bake). Default browser. |
| App store | [Bazaar](https://github.com/secureblue/bazaar-rpm) — they **removed GNOME Software and Plasma Discover**, added a curated catalog, and **blocklisted every Flathub browser except GNOME Web** ([PR #1898](https://github.com/secureblue/secureblue/pull/1898)) | Bazaar gone. **GNOME Software** or **Plasma Discover** back. **Unfiltered Flathub**. |
| User namespaces | Off for normal apps; Trivalent is the special case | **On**, so Brave’s Chromium sandbox can start |

That last row is a real security trade. Brave is **not** SELinux-confined like Trivalent. You get origin Brave; you do not get their extra confinement. Everything else is still their hardened OS.

We did **not** gut SELinux, kernel args, `hardened_malloc`, disk encryption, or Secure Boot enrollment. Calling this “insecure Fedora” is false. Calling it “identical to secureblue” is also false.

---

## Images (rebuilt every day, 08:00 UTC)

| Image | Desktop | GPU |
| --- | --- | --- |
| `unwoke-silverblue` | GNOME | Nouveau |
| `unwoke-silverblue-nvidia-open` | GNOME | NVIDIA open modules (GTX 16xx / RTX and newer) |
| `unwoke-kinoite` | KDE Plasma | Nouveau |
| `unwoke-kinoite-nvidia-open` | KDE Plasma | NVIDIA open modules (GTX 16xx / RTX and newer) |

Published as `ghcr.io/sergi270710267/<name>:latest`. All four are **public**. No GitHub login to pull.

---

## Install (one command)

Already on secureblue (or any Fedora Atomic):

```bash
rpm-ostree rebase ostree-unverified-registry:ghcr.io/sergi270710267/unwoke-silverblue:latest
systemctl reboot
```

Empty disk: flash a [secureblue ISO](https://secureblue.dev/install), install it (encrypt, wheel, enroll their Secure Boot key), then the two lines above. You are switching the image, not doing a second install.

KDE → `unwoke-kinoite`. NVIDIA → add `-nvidia-open`.

After reboot: Brave is the browser, Bazaar/Trivalent are gone, updates follow **this** repo’s daily rebuild.

Optional signed rebase (after the unsigned boot):

```bash
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/sergi270710267/unwoke-silverblue:latest
systemctl reboot
```

```bash
cosign verify --key cosign.pub ghcr.io/sergi270710267/unwoke-silverblue
```

---

## USB ISO

The OS **is** the GHCR image. A flashable ISO is optional.

Actions → **iso** → Run workflow → pick the image → download the artifact (kept 14 days). GitHub will not host a 3 GB ISO as a normal release.

---

## How it stays current

Not a git fork. Forks rot.

```yaml
base-image: ghcr.io/secureblue/silverblue-main-hardened
image-version: latest
```

GitHub Actions pulls that every day, then re-applies only this overlay. Your machine updates with normal `rpm-ostree`.

| Change | File |
| --- | --- |
| Packages | `recipes/common.yml` |
| Browser / first-boot | `files/scripts/apply-unwoke.sh` |
| GNOME favorites | `files/gschema-overrides/zz2-unwoke.gschema.override` |

---

## License

Overlay files: MIT. Fedora, secureblue, BlueBuild, Brave, Trivalent: their licenses. Unaffiliated with secureblue.
