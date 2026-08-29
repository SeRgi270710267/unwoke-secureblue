# Unwoke SecureBlue

**secureblue’s hardening. Brave Origin, stock Trivalent, or no browser. Terminal, no curator store.**

The product name is **Unwoke SecureBlue**. *Unwoke* is the modifier (adjective/verb). *SecureBlue* is one word, S and B capped — not “Secure Blue”, not `unwoke-secureblue` in titles. Git and GHCR stay lowercase (`unwoke-secureblue`, `unwoke-silverblue`) because registries and rebase commands are slugs.

This is a daily overlay on official [secureblue](https://secureblue.dev) images. It is **not** a fork and **not** affiliated with them. Their kernel hardening, `hardened_malloc`, SELinux, no Xwayland by default, and automatic updates stay. We strip **Bazaar** and GUI stores on every image. Default images also strip Trivalent and ship **Brave Origin**. `*-trivalent` keeps stock Trivalent (patches + SELinux) and adds extra reversible Chromium policies. `*-browserless` ships no house browser.

Site: [sergi270710267.github.io/unwoke-secureblue](https://sergi270710267.github.io/unwoke-secureblue/). Overlay delta and toggles: [Features](https://sergi270710267.github.io/unwoke-secureblue/features/). Wallpaper/lock/accent: [Brand](https://sergi270710267.github.io/unwoke-secureblue/brand/). What changed: [Changelog](https://sergi270710267.github.io/unwoke-secureblue/changelog/) (rebuilt with the site from public git subjects). Stock secureblue FAQ/features/install are mirrored daily under `/secureblue/` (Apache-2.0, not affiliated); our pages are never overwritten.

Images: `ghcr.io/sergi270710267/unwoke-silverblue` · `unwoke-kinoite` · `*-nvidia-open` · `*-trivalent` · `*-browserless`

---

## Why this exists (receipts, not vibes)

Stock secureblue is a serious hardened Fedora Atomic. It also ships a house browser and a house app store that decide what you may install.

| | Stock [secureblue](https://secureblue.dev) | Origin images | Trivalent images (`*-trivalent`) | Browserless images (`*-browserless`) |
| --- | --- | --- | --- | --- |
| Browser | [Trivalent](https://github.com/secureblue/Trivalent) — their Chromium, default, SELinux-confined | **[Brave Origin](https://brave.com/origin/linux/)** standalone RPM (`brave-origin`). Default browser. Runs in `brave_t`. | **Stock Trivalent** (same patches + SELinux) plus extra reversible policies | **None.** No Trivalent, no Origin. `harden_userns` is stock (Flatpak only). |
| App store | [Bazaar](https://github.com/secureblue/bazaar-rpm) — curated catalog | **None.** No Flathub until `ujust set-flathub verified`. | **None.** Same. | **None.** Same. |
| User namespaces | Off for unconfined; on for Flatpak and Trivalent | Same, plus `brave_t` on their userns allow-list so Origin’s sandbox can start | Same as stock. No `brave_t`. | Same as stock with Trivalent gone: unconfined blocked, Flatpak allowed, no extra domain |

`brave_t` (Origin images only) is an unconfined-like domain so Brave Origin can run. It is **not** Trivalent’s tight confinement. Trivalent and browserless do not load it.

`*-trivalent` equals stock on the house browser and is stricter on extra Chromium policies + house locks. Extra JSON is not a new compiler patch.

Browserless is safer than Origin **until you install a browser**. Easy host installs are blocked until `ujust set-allow-browsers on ALLOW` (Flatpak mask + rpm-ostree exclude). That is a seatbelt: toolbox, brew, AppImage, and `rpm-ostree --disableexcludes` still work. It is not a Trivalent replacement.

What we *can* do on Origin and Trivalent is force Chromium enterprise policies and keep their `ujust` surface. Stock commands still work (`ujust set-unconfined-userns`, `ujust set-kargs-hardening`, `ujust audit-secureblue`, …). Overlay extras:

```bash
ujust unwoke-status
ujust audit-unwoke

# Origin and Trivalent (each has on/off; restart the browser after policy changes)
# set-trivalent-* is the same pack under a clearer name on -trivalent images
ujust set-brave-hardening on|off     # HTTPS, no metrics, no autofill/passwords (default on)
ujust set-brave-devices on|off       # camera/mic/geo/USB/BT/serial blocked (default on)
ujust set-brave-jitless on|off       # no JS JIT; breaks some sites (default on)
ujust set-brave-extensions block|allow
ujust set-brave-isolation on|off     # no WebGL/WebGPU; SitePerProcess (default on)
ujust set-brave-sandbox on|off       # audio sandbox, no screen capture, no JS optimizer
ujust set-brave-devtools lock|allow  # default allow (opt-in)
ujust set-brave-bubblejail on|off    # Origin only; default on; GPU may break
ujust set-trivalent-network-sandbox on|off  # Trivalent only; may clear cookies
ujust set-trivalent-referrers on|off        # Trivalent only; punycode + strip referrers

# All flavors
ujust set-flathub verified|full|off  # default off both flavors; verified = stock
ujust set-bluetooth on|off           # default off; Wi-Fi stays
ujust set-toolbox on|off             # default off; /usr/bin/toolbox is a wrapper
ujust set-extra-daemons on|off       # default off (Avahi + ModemManager)
ujust set-stock-nags on|off          # default off (their deprecation/update-verify/flatpak-setup)
ujust set-flatpak-lockdown on|off    # default on; apps need Flatseal
ujust set-brew on|off                # default off (stock ships Homebrew)
ujust set-camera-mic on|off          # default locked (uvcvideo + capture nodes)
ujust set-admin-split on|off|add NAME  # wheel GUI lock once a daily user exists

# Browserless only
ujust set-allow-browsers on ALLOW
ujust set-allow-browsers off

# Theme
ujust set-unwoke-theme apply     # wallpaper + accent again
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
| `unwoke-silverblue-trivalent` | GNOME | Nouveau | Trivalent |
| `unwoke-silverblue-nvidia-open-trivalent` | GNOME | NVIDIA open | Trivalent |
| `unwoke-kinoite-trivalent` | KDE Plasma | Nouveau | Trivalent |
| `unwoke-kinoite-nvidia-open-trivalent` | KDE Plasma | NVIDIA open | Trivalent |
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

That first switch **cannot** check our stamp yet (your PC does not have our key). After that reboot, a first-boot service **queues the signed image**. Reboot **one more time** when `rpm-ostree status` shows a staged signed deployment (or after a few minutes on the network). From then on, updates must match our `cosign.pub`. After the first graphical login, `ujust setup` (also an autostart window) explains the locks; `ujust why` if something looks broken. Nothing unlocks unless you pick it. Everyday tasks (apps, Bluetooth, camera, USB, updates) with the secure path first: [Tutorials](https://sergi270710267.github.io/unwoke-secureblue/tutorials/).

If it did not auto-stage (no network on first boot), do it yourself:

```bash
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/sergi270710267/unwoke-silverblue:latest
systemctl reboot
```

Empty disk: flash a [secureblue ISO](https://secureblue.dev/install) first (encrypt, wheel, enroll their Secure Boot key), then the commands above.

KDE → `unwoke-kinoite`. NVIDIA → add `-nvidia-open`. Keep Trivalent → add `-trivalent`. No browser → add `-browserless` (e.g. `unwoke-silverblue-browserless`).

```bash
cosign verify --key cosign.pub ghcr.io/sergi270710267/unwoke-silverblue
```

---

## USB ISO (empty disk, no stock first)

The OS **is** the GHCR image. A flashable ISO wraps that image so you do not install stock secureblue first.

- On demand: Actions → **iso** → Run workflow → pick the image → artifact (14 days).
- Weekly (Sunday 10:00 UTC): Silverblue/Kinoite × Origin/Trivalent pushed to `ghcr.io/sergi270710267/<name>-iso:latest`. Pull with `oras`, verify with `cosign.pub`.
- GitHub will not host a 3 GB ISO as a normal release. Not Ventoy. Enroll the **secureblue** Secure Boot key (kernel is theirs).

Stock-ISO-then-rebase still works.

---

## How it stays current (and how the signatures work)

Not a git fork of `secureblue/secureblue`. Forks rot. We pull their **already-built, already-signed** images.

```yaml
base-image: ghcr.io/secureblue/silverblue-main-hardened
image-version: latest
```

**Trust chain**

1. secureblue builds and **cosign-signs** `ghcr.io/secureblue/…-hardened`.
2. Our CI downloads [their public key](https://github.com/secureblue/secureblue/blob/live/cosign.pub), checks it still matches `keys/secureblue.pub` in this repo, **`cosign verify`s the base**, then **pins that digest** so `:latest` cannot swap mid-build. A canary job inspects that signed base with **crane export** (does not run it, does not docker-pull it) and **fails the overlay** if the stock image names this repo, our GHCR, or `/usr/share/unwoke`. Cosign does not protect against a hostile signer; the canary only catches an in-the-clear targeted payload. After rebase, your PC follows **our** GHCR, not theirs.
3. We drop Bazaar+GUI stores+full `brave-browser`. Origin images also drop Trivalent, then layer **Brave Origin** (`brave-origin`) and a `brave_t` SELinux domain. `-trivalent` images keep stock Trivalent and add extra policies. Browserless images drop Trivalent and skip Origin. Then we **cosign-sign our image** with `cosign.pub` in this repo.
4. Your PC pulls `ghcr.io/sergi270710267/unwoke-…` and, after the signed rebase, verifies **our** signature.

That is as close as an overlay gets to “updating from their source” without merging their git. We do **not** rebuild their kernel or re-run their SLSA pipeline; we inherit whatever they already shipped, after checking their signature.

Rebuilds: **08:00 and 20:00 UTC**, plus every recipe push.

Factory extras (this repo, not the desktop):

- **Harden-Runner** on CI (audit outbound traffic)
- GitHub Actions **pinned to commit SHAs**
- **SLSA-style provenance** attached to each published image (`attest-build-provenance`)
- BlueBuild CLI install is **signature-checked**
- **crane** for canary/inspect is checksum-pinned (`v0.20.3`); Atomic images are not docker-pulled
- Published images are **inspected after each build** and twice daily (`verify.yml`)
- One reused GitHub issue (`factory-alarm`) when the overlay factory is red; closed when it is green
- Stock `ujust harden-flatpak` is a trampoline to `/usr/libexec/unwoke/harden-flatpak.sh` (their Python is not executed)

We do **not** use a hardware signing key. `cosign.key` lives only as the GitHub secret `SIGNING_SECRET`. A YubiKey would be stricter; it is not wired up.

Your machine then follows this repo with normal `rpm-ostree` updates.

| Change | File |
| --- | --- |
| Packages | `recipes/common.yml` (stores); `remove-trivalent.sh` on Origin/browserless |
| Browser / first-boot | `files/scripts/apply-{unwoke,brave,trivalent,browserless}.sh` |
| Brave SELinux / userns | `files/scripts/install-brave-selinux.sh`, `files/system/usr/share/unwoke/selinux/` (Origin only) |
| ujust extras | `files/justfiles/unwoke.just`, `files/system/usr/libexec/unwoke/toggles.sh` |
| GNOME favorites | `files/gschema-overrides/zz2-unwoke*.gschema.override` |

---

## License

Overlay files: MIT. Fedora, secureblue, BlueBuild, Brave, Trivalent: their licenses. Unaffiliated with secureblue.
