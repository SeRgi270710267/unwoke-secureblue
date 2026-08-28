# unwoke-secureblue

A personal [secureblue](https://secureblue.dev) overlay. It is **not** official secureblue.

You keep secureblue’s hardening (hardened kernel settings, `hardened_malloc`, SELinux, no Xwayland by default, automatic updates, and the rest). This repo only changes the parts you asked for, and **rebuilds every day from the latest official secureblue images**, so you stay current without forking their tree.

## What this image changes

| Stock secureblue | This overlay |
| --- | --- |
| [Trivalent](https://github.com/secureblue/Trivalent) as the browser | **Official Brave RPM** from [brave.com/linux](https://brave.com/linux/) (`brave-browser`, default browser) |
| [Bazaar](https://github.com/secureblue/bazaar-rpm) (curated store + browser blocklist) | Bazaar removed. **GNOME Software** (Silverblue) or **Plasma Discover** (Kinoite) + unfiltered Flathub |
| Unprivileged user namespaces only for Trivalent | Unconfined userns **on by default**, so Brave’s Chromium sandbox can start |

Everything else is still secureblue.

Brave is not SELinux-confined the way Trivalent is. Turning unconfined user namespaces on is the tradeoff that lets a normal Chromium browser run. That is a real security reduction versus stock secureblue. You wanted origin Brave; this is how that works on this OS.

## Images (built daily)

Published to GHCR as `ghcr.io/sergi270710267/<name>:latest`:

| Image | Desktop | GPU |
| --- | --- | --- |
| `unwoke-silverblue` | GNOME | Nouveau |
| `unwoke-silverblue-nvidia-open` | GNOME | NVIDIA open kernel modules (Turing / GTX 16xx and newer, including RTX) |
| `unwoke-kinoite` | KDE Plasma | Nouveau |
| `unwoke-kinoite-nvidia-open` | KDE Plasma | NVIDIA open kernel modules (Turing+) |

Pick **nvidia-open** if you have a modern NVIDIA GPU. Use the non-nvidia image on Intel/AMD.

## Easiest install (one command)

**If you already have secureblue installed**, this is the whole thing. Pick the name that matches your box (KDE / NVIDIA below). Open a terminal:

```bash
rpm-ostree rebase ostree-unverified-registry:ghcr.io/sergi270710267/unwoke-silverblue:latest
systemctl reboot
```

After reboot you are on this image. Brave is the browser. Bazaar and Trivalent are gone. Daily updates keep following this repo.

**If the PC is empty:** flash a normal [secureblue ISO](https://secureblue.dev/install) (same desktop/GPU), install it (encrypt disk, wheel group, enroll their Secure Boot key), then run the two lines above. You are not reinstalling the OS a second time — you just switch the image.

**One GitHub click so that command can pull:** repo → **Packages** → each `unwoke-*` package → Package settings → Change visibility → **Public**. Until that is public, Linux cannot download the image.

Names: `unwoke-kinoite` for KDE, add `-nvidia-open` if you have a modern NVIDIA GPU (GTX 16xx / RTX).

## Your own ISO

When you want a USB installer of *this* image, not stock secureblue:

### From GitHub Actions (no Linux box needed)

1. Wait until the **bluebuild** workflow has published the image you want.
2. Actions → **iso** → Run workflow → pick the image.
3. Download the artifact (ISO + SHA256). Artifacts expire; this is for flashing, not long-term hosting.

### On a Linux machine

```bash
# after the image exists on GHCR
sudo bluebuild generate-iso --iso-name unwoke-silverblue.iso \
  image ghcr.io/sergi270710267/unwoke-silverblue
```

Flash that ISO the same way as a secureblue ISO.

## How updates stay in sync with secureblue

This is **not** a git fork of `secureblue/secureblue`. Forks rot.

Each recipe’s `base-image` is the official image, for example:

```yaml
base-image: ghcr.io/secureblue/silverblue-main-hardened
image-version: latest
```

GitHub Actions rebuilds **every day at 08:00 UTC** (and on every push). That pulls the newest secureblue image, then re-applies only this overlay (Brave, no Trivalent, no Bazaar, GNOME Software/Discover, userns). Your installed machine then picks it up with secureblue’s normal automatic `rpm-ostree` updates.

To change behavior, edit files in this repo. Do not merge secureblue’s git history.

| Want to… | Edit |
| --- | --- |
| Drop/add a package | `recipes/common.yml` or the DE recipe |
| Change default browser / first-boot | `files/scripts/apply-unwoke.sh`, `files/system/usr/libexec/unwoke/first-boot.sh` |
| Change GNOME favorites | `files/gschema-overrides/zz2-unwoke.gschema.override` |
| Add another DE / GPU flavor | New file under `recipes/` + a line in `.github/workflows/build.yml` |

## One-time GitHub setup (signing + Actions)

New GitHub repos start with Actions off and no signing key.

1. Open the repo **Actions** tab and enable workflows if GitHub asks.
2. Generate a cosign key **with an empty password**:
   ```bash
   cosign generate-key-pair
   ```
3. Put `cosign.pub` in the repo root (already done if this file is here).
4. Repo **Settings → Secrets and variables → Actions → New repository secret**
   - Name: `SIGNING_SECRET`
   - Value: full contents of `cosign.key`
5. Re-run the **bluebuild** workflow.
6. After the first successful package publish, set each GHCR package to **Public**.

`cosign.key` must never be committed. It is in `.gitignore`.

## Verify a signed image

```bash
cosign verify --key cosign.pub ghcr.io/sergi270710267/unwoke-silverblue
```

## License

Overlay files in this repository are MIT. Upstream secureblue, Fedora, BlueBuild, Brave, and Trivalent remain under their own licenses. This project is unaffiliated with secureblue.
