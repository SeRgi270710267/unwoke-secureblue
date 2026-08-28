# Unwoke SecureBlue — development handoff

Use this file to resume after a closed chat. Local clone: `C:\Users\UsEr1002\.grok\bin\unwoke-secureblue`. GitHub: `SeRgi270710267/unwoke-secureblue`. Site: https://sergi270710267.github.io/unwoke-secureblue/

**Not affiliated with secureblue.** Overlay on their signed Fedora Atomic images. Not a fork.

## Product name

Display: **Unwoke SecureBlue** (`Unwoke` = modifier; `SecureBlue` = one word, S+B). Slugs stay lowercase (`unwoke-secureblue`, `unwoke-silverblue`).

## Architecture (do not change without a reason)

- BlueBuild overlay on official signed secureblue images.
- Eight GHCR images: silverblue / kinoite × nvidia-open × browserless.
- `ghcr.io/sergi270710267/<name>:latest`. Cosign with a GitHub Actions secret (not a hardware key).
- First rebase is `ostree-unverified-registry`; first-boot promotes `ostree-image-signed`.
- Image CI: `.github/workflows/build.yml` (paths-ignore docs). Pages: `.github/workflows/pages.yml` from `docs/`.
- Daily image rebuilds 08:00 and 20:00 UTC. Docs mirror of secureblue.dev at 09:30 UTC into generated `docs/secureblue/` (gitignored).

## What the overlay does

**Strip:** Trivalent, Bazaar, GNOME Software, Plasma Discover, leftover launchers.

**Origin flavor:** `brave-origin` RPM (`/opt/brave.com/brave-origin/brave`), not `brave-browser`. Fat SELinux `brave_t` (`unconfined_domain`) + CIL userns allow-list. `harden_userns` stays on. SUID stripped on Origin. Default browser.

**Browserless:** nothing put back. No `brave_t`. Flatpak mask + rpm exclude until `ujust set-allow-browsers on ALLOW` (seatbelt: toolbox/brew/AppImage/`--disableexcludes` still work).

**Policies** (Origin, default on, each reversible):

- hardening — HTTPS, no metrics/sync/autofill/passwords/translate/WebRTC IP leak
- devices — camera/mic/geo/USB/BT/serial/HID/FS API
- jitless — `DefaultJavaScriptJitSetting: 2`
- extensions — blocklist `*`

**Flathub:** Origin default `verified`; browserless default `off`; `ujust set-flathub verified|full|off`.

**Flatpak lockdown:** default on (stock’s cuts, system + user). `ujust set-flatpak-lockdown off`.

**Bubblejail:** Origin launcher wrapper, default off.

**Theme:** wallpaper + lock JPG, GNOME `accent-color=blue` + GTK `#3b6cff`, KDE `59,108,255`, GDM wallpaper. `ujust set-unwoke-theme apply`. No classic screensaver (GNOME does not have one). No tight `brave_t` jail (intentionally not shipped).

Site palette: navy `#050a16` / `#0a1328`, accent `#3b6cff`. Brand tab shows the wallpapers.

## ujust extras

```
ujust unwoke-status
ujust audit-unwoke
ujust set-flathub verified|full|off
ujust set-flatpak-lockdown on|off
ujust set-brave-hardening on|off
ujust set-brave-devices on|off
ujust set-brave-jitless on|off
ujust set-brave-extensions block|allow
ujust set-brave-bubblejail on|off
ujust set-unwoke-theme apply
ujust set-allow-browsers on ALLOW   # browserless
```

Stock `ujust` still works.

## Honest leftover gaps (cannot close as an overlay)

- Trivalent/Vanadium Chromium patches
- Tight SELinux for Origin
- Hardware signing key / their SLSA for the *overlay* key
- GNOME Shell custom hex accent (named `blue` only)

## Key paths

- Recipes: `recipes/*.yml` (`common.yml` + `brave.yml` or `browserless.yml`)
- Scripts: `files/scripts/`, `files/system/usr/libexec/unwoke/`
- Policies: `files/system/usr/share/unwoke/*.json` and `usr/etc/brave-origin/policies/managed/`
- Theme: `files/system/usr/share/backgrounds/unwoke/`, gschema `zz1-unwoke-theme.gschema.override`
- Site: `docs/` (Pages). Mirror template: `.github/scripts/mirror-template.html`

## Recent work in this chat arc

1. Brave Origin + no GUI store + fat `brave_t` instead of disabling `harden_userns`
2. Browserless + allow-browsers gate
3. Site (secureblue.dev-inspired), docs mirror, conduct/donate/post-install/contributing tabs
4. Lime → real blue site palette
5. Reversible overlay toggles (Flathub, policies, lockdown, JIT-less default on)
6. Default wallpaper / lock / accent
7. Site updated to document all of the above + Brand tab
8. Auto changelog tab: Pages job runs `docs/_tools/generate-changelog.py` from public git subjects (no bodies/diffs). Output gitignored `docs/changelog/`. Pages runs on every `main` push so overlay commits show up without waiting for the daily mirror cron.

Image-side theme and toggles land on the **next image rebuild**, not Pages. Docs-only pushes should not rebuild images (`build.yml` paths-ignore).

## Tomorrow

- Confirm GHCR images after CI actually contain wallpaper + policy packs (`ujust unwoke-status` on a rebase).
- Hard-refresh Pages if Brand wallpapers look cached.
- Do not start a tight `brave_t` jail unless the owner asks again and accepts breakage.
- Do not put Trivalent back. Do not add a GUI store. Do not add xscreensaver.
