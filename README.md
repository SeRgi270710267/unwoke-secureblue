<p align="center">
  <img src="docs/assets/hero.jpg" alt="Unwoke SecureBlue — navy hexagonal shield" width="920">
</p>

<p align="center">
  <img src="docs/assets/logo.svg" width="72" alt="">
</p>

<p align="center">
  <img src="docs/assets/wordmark.svg" alt="Unwoke SecureBlue" width="420">
</p>

<p align="center">
  <strong>secureblue’s hardening. Recommended: stock Trivalent plus extra locks.<br>Or Brave Origin, or no browser. Terminal, no curator store.</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-source--available-3b6cff?style=for-the-badge&amp;labelColor=050a16" alt="Source-available"></a>
</p>

<p align="center">
  <img src="docs/assets/divider.svg" width="420" alt="">
</p>

> **Not affiliated with secureblue.** Overlay on their signed Fedora Atomic images. **Not a fork.** Their kernel hardening, `hardened_malloc`, SELinux, no Xwayland by default, and automatic updates stay.

The product name is **Unwoke SecureBlue**. *Unwoke* is the modifier. *SecureBlue* is one word (S and B capped) — not “Secure Blue”, not `unwoke-secureblue` in titles. Git and GHCR stay lowercase (`unwoke-secureblue`, `unwoke-silverblue`) because registries and rebase commands are slugs.

We strip **Bazaar** and GUI stores on every image.

| | **Trivalent** `*-trivalent` | **Origin** (unsuffixed) | **Browserless** `*-browserless` |
| --- | --- | --- | --- |
| | **Recommended default** | Named choice | Named choice |
| Browser | Stock [Trivalent](https://github.com/secureblue/Trivalent) jail + extra reversible Chromium policies | [Brave Origin](https://brave.com/origin/linux/) RPM in `brave_t` (looser SELinux) | None. Seatbelt until `ujust set-allow-browsers on ALLOW` |
| Store | None | None | None |
| Userns | Stock (Flatpak + Trivalent) | Stock + `brave_t` allow-list | Stock with Trivalent gone |

`*-trivalent` equals stock on the house browser and is stricter on extra Chromium policies + house locks. Extra JSON is not a new compiler patch. `brave_t` is **not** Trivalent’s tight confinement.

---

## Distribution

The git repository stays public so the recipes, locks, and signing key can be audited. Prebuilt images, USB images, and the full site are **invite-only**. This page does not contain install commands or registry names. The public site is a notice. The docs site asks for a GitHub login and an invitation.

The pull credential is a classic personal access token with only the `read:packages` scope, stored on that machine as `/etc/ostree/auth.json` mode `0600`. It is not baked into the image. An invitee cannot grant anyone else.

People who already have a copy keep the license grants below.

---

## Why this exists (receipts, not vibes)

Stock secureblue is a serious hardened Fedora Atomic. It also ships a house browser and a house app store that decide what you may install.

| | Stock [secureblue](https://secureblue.dev) | Origin | Trivalent | Browserless |
| --- | --- | --- | --- | --- |
| Browser | Trivalent — their Chromium, SELinux-confined | Brave Origin standalone RPM. Runs in `brave_t` | Stock Trivalent + extra reversible policies | None |
| App store | [Bazaar](https://github.com/secureblue/bazaar-rpm) | **None.** Flathub off until `ujust set-flathub verified` | **None.** Same | **None.** Same |
| User namespaces | Off for unconfined; on for Flatpak and Trivalent | Same, plus `brave_t` on their userns allow-list | Same as stock. No `brave_t` | Unconfined blocked, Flatpak allowed, no extra domain |

Browserless is safer than Origin **until you install a browser**. Easy host installs are blocked until `ujust set-allow-browsers on ALLOW` (Flatpak mask + rpm-ostree exclude). Seatbelt only: toolbox, brew, AppImage, and `rpm-ostree --disableexcludes` still work.

Stock `ujust` still works (`ujust set-unconfined-userns`, `ujust set-kargs-hardening`, `ujust audit-secureblue`, …). We did **not** gut SELinux, kernel args, `hardened_malloc`, disk encryption, or Secure Boot enrollment.

<details>
<summary><strong>Overlay ujust extras</strong></summary>

```bash
ujust unwoke-status
ujust audit-unwoke
ujust setup
ujust why

# Origin and Trivalent (restart the browser after policy changes)
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
ujust set-flathub verified|full|off  # default off; verified = stock
ujust set-bluetooth on|off           # default off; Wi-Fi stays
ujust set-toolbox on|off             # default off; /usr/bin/toolbox is a wrapper
ujust set-extra-daemons on|off       # default off (Avahi + ModemManager)
ujust set-stock-nags on|off          # default off
ujust set-flatpak-lockdown on|off    # default on
ujust set-brew on|off                # default off
ujust set-camera-mic on|off          # default locked
ujust set-admin-split on|off|add NAME
ujust set-unwoke-theme apply

# Browserless only
ujust set-allow-browsers on ALLOW
ujust set-allow-browsers off
```

</details>

Twelve images: GNOME or KDE, Nouveau or NVIDIA open, and Trivalent, Brave Origin, or no browser. Rebuilt 08:00 and 20:00 UTC. Names are not listed here.

---

## USB ISO

A flashable ISO is built in Actions. It is not uploaded as an artifact or a release. On a public repository those downloads are available to anyone with a GitHub account. An invited machine pulls the ISO from a private package. The installer asks for the invite credential and refuses to finish without it.

---

## How it stays current

Not a git fork of `secureblue/secureblue`. Forks rot. We pull their **already-built, already-signed** images.

<details>
<summary><strong>Trust chain and factory</strong></summary>

1. secureblue builds and **cosign-signs** their hardened images.
2. Our CI checks [their public key](https://github.com/secureblue/secureblue/blob/live/cosign.pub) still matches `keys/secureblue.pub`, **`cosign verify`s the base**, then **pins that digest**. A canary inspects that signed base with **crane export** (does not run it, does not docker-pull it) and **fails the overlay** if the stock image names this repo, our registry, or `/usr/share/unwoke`. After rebase, an invited machine follows **our** registry, not theirs.
3. We drop Bazaar + GUI stores. Origin also drops Trivalent and layers Brave Origin + `brave_t`. `-trivalent` keeps stock Trivalent and adds extra policies. Browserless drops Trivalent and skips Origin. Then we **cosign-sign our image** with `cosign.pub` in this repo.
4. An invited machine pulls our image and, after the signed rebase, verifies **our** signature. The public key is how they check the signature. It is not a pull secret.

We do **not** rebuild their kernel or re-run their SLSA pipeline.

Factory extras (this repo, not the desktop): Harden-Runner; Actions pinned to SHAs; checksum-pinned crane `v0.20.3`; inspect after each bake and twice daily; one reused issue per alarm label; `pr-gate` + ruleset `main-strict`; stock `ujust harden-flatpak` is a trampoline to Unwoke’s script. Public provenance attestations are not published. The public site is an invitation notice, not the old docs.

We do **not** use a hardware signing key. `cosign.key` lives only as the GitHub secret `SIGNING_SECRET`.

| Change | File |
| --- | --- |
| Packages | `recipes/common.yml`; `remove-trivalent.sh` on Origin/browserless |
| Browser / first-boot | `files/scripts/apply-{unwoke,brave,trivalent,browserless}.sh` |
| Brave SELinux / userns | `files/scripts/install-brave-selinux.sh` (Origin only) |
| ujust extras | `files/justfiles/unwoke.just`, `files/system/usr/libexec/unwoke/toggles.sh` |
| GNOME favorites | `files/gschema-overrides/zz2-unwoke*.gschema.override` |

</details>

Stock FAQ/features/install are still mirrored in-tree by the Pages workflow (Apache-2.0, not affiliated). That mirror is not deployed to the public site. Pickup file for this repo: [`PROGRESS.md`](PROGRESS.md).

The GitHub factory (not the desktop) pins Actions to commit SHAs, starts each workflow at `permissions: {}`, scans for secrets, and ShellChecks the scripts. Dependabot opens one grouped Actions PR and does not move the image-builder pin. Agents: [`AGENTS.md`](AGENTS.md). Reports: [`SECURITY.md`](SECURITY.md). Owner steps for the private registry: [`invite/OWNER-STEPS.md`](invite/OWNER-STEPS.md).

---

## License

The overlay is the Unwoke Source-Available License 1.0 (`LICENSE`, SPDX `LicenseRef-Unwoke-SA-1.0`). The source stays readable. Redistributing the overlay, or a build that includes it, needs permission. Earlier public versions were MIT. A copy already obtained under that grant keeps it. secureblue, Universal Blue, and the upstream snapshots stay Apache-2.0 (`NOTICE`, `LICENSES/Apache-2.0.txt`). Fedora, BlueBuild, Brave, and Trivalent keep their own licenses. The name and logo are reserved for official signed builds (`TRADEMARK.md`). Unaffiliated with secureblue.
