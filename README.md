# unwoke-secureblue

**secureblue’s hardening. Brave Origin. Terminal, no curator store.**

This is a daily overlay on official [secureblue](https://secureblue.dev) images. It is **not** a fork and **not** affiliated with them. Their kernel hardening, `hardened_malloc`, SELinux, no Xwayland by default, and automatic updates stay. We only strip the two product decisions that lock the desktop: **Trivalent** and **Bazaar**. No GUI software store is added back.

Images: `ghcr.io/sergi270710267/unwoke-silverblue` · `unwoke-kinoite` · `*-nvidia-open`

---

## Why this exists (receipts, not vibes)

Stock secureblue is a serious hardened Fedora Atomic. It also ships a house browser and a house app store that decide what you may install.

| | Stock [secureblue](https://secureblue.dev) | This overlay |
| --- | --- | --- |
| Browser | [Trivalent](https://github.com/secureblue/Trivalent) — their Chromium, default, SELinux-confined | **[Brave Origin](https://brave.com/origin/linux/)** standalone RPM (`brave-origin`, not full `brave-browser`). Default browser. Runs in `brave_t`. |
| App store | [Bazaar](https://github.com/secureblue/bazaar-rpm) — curated catalog, most Flathub browsers blocklisted ([PR #1898](https://github.com/secureblue/secureblue/pull/1898)) | **None.** Flathub remote is added for `flatpak` CLI. Use `brew` / `rpm-ostree` for the rest. |
| User namespaces | Off for unconfined; on only for Flatpak and Trivalent | **Same.** `harden_userns` stays on. `brave_t` is added to their userns allow-list so Brave’s Chromium sandbox can start. Other unconfined apps stay blocked. |

`brave_t` is an unconfined-like domain (so Brave Origin can actually run) that is allowed to create user namespaces. It is **not** Trivalent’s tight confinement, and you do not get Trivalent’s Chromium patches. Those patches live in their browser source. Brave Origin cannot grow them.

What we *can* do on Brave Origin is force Chromium enterprise policies and keep their `ujust` surface. Stock commands still work (`ujust set-unconfined-userns`, `ujust set-kargs-hardening`, `ujust audit-secureblue`, …). Overlay extras:

```bash
ujust unwoke-status
ujust audit-unwoke
ujust set-brave-hardening on    # default: HTTPS-only, no WebRTC IP leak, no metrics. Restart Brave Origin.
ujust set-brave-hardening off
ujust set-brave-jitless on      # optional; breaks some sites. Restart Brave Origin.
```

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

That first switch **cannot** check our stamp yet (your PC does not have our key). After that reboot, a first-boot service **queues the signed image**. Reboot **one more time** when `rpm-ostree status` shows a staged signed deployment (or after a few minutes on the network). From then on, updates must match our `cosign.pub`.

If it did not auto-stage (no network on first boot), do it yourself:

```bash
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/sergi270710267/unwoke-silverblue:latest
systemctl reboot
```

Empty disk: flash a [secureblue ISO](https://secureblue.dev/install) first (encrypt, wheel, enroll their Secure Boot key), then the commands above.

KDE → `unwoke-kinoite`. NVIDIA → add `-nvidia-open`.

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
3. We layer **Brave Origin** (`brave-origin`), drop Trivalent+Bazaar+GUI stores+full `brave-browser`, load a Brave Origin SELinux domain, and **cosign-sign our image** with `cosign.pub` in this repo.
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
