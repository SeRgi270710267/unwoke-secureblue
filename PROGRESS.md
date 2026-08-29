# Unwoke SecureBlue — development handoff

**Read this first** if continuing in a new chat. Working tree was clean and pushed.

- Branch: `main`, synced to `origin/main` when this file was last committed.
- Local clone: `C:\Users\UsEr1002\.grok\bin\unwoke-secureblue`
- GitHub: `SeRgi270710267/unwoke-secureblue`
- Site: https://sergi270710267.github.io/unwoke-secureblue/
- Brand: https://sergi270710267.github.io/unwoke-secureblue/brand/
- Changelog: https://sergi270710267.github.io/unwoke-secureblue/changelog/ (generated at Pages deploy; gitignored)

**How to resume:** open the clone, say you are continuing Unwoke SecureBlue from `PROGRESS.md`, and do not rebuild images for docs-only work.

**Not affiliated with secureblue.** Overlay on their signed Fedora Atomic images. Not a fork.

## Product name

Display: **Unwoke SecureBlue** (`Unwoke` = modifier; `SecureBlue` = one word, S+B). Slugs stay lowercase (`unwoke-secureblue`, `unwoke-silverblue`).

## Architecture (do not change without a reason)

- BlueBuild overlay on official signed secureblue images.
- Twelve GHCR images: silverblue / kinoite × nvidia-open × (Origin | trivalent | browserless).
- `ghcr.io/sergi270710267/<name>:latest`. Cosign with a GitHub Actions secret (not a hardware key).
- First rebase is `ostree-unverified-registry`; first-boot promotes `ostree-image-signed`.
- Image CI: `.github/workflows/build.yml` (paths-ignore docs). Pages: `.github/workflows/pages.yml` from `docs/`.
- Base canary: `.github/scripts/scan-base-canary.sh` runs on the four official bases *before* the 12-image matrix. Inspects (docker create/copy, never run) for needles in `.github/scripts/base-canary-needles.txt`. Hit = no overlay. Does not catch a generic backdoor or obfuscation. Stock still cannot push to this GitHub/GHCR; user machines follow Unwoke GHCR after signed rebase.
- Do not exec stock `harden_flatpak.py`. Unwoke uses `files/system/usr/libexec/unwoke/harden-flatpak.sh`. Snapshots: `harden_flatpak.py` + `flatpak.just` watched by `.github/scripts/check-upstream-watch.sh`. Drift fails the image build until reviewed.
- Stock MOTD replaced (`usr/libexec/secureblue-motd`). User nags masked by default: deprecation notice, update-verification, flatpak-setup (`ujust set-stock-nags on` to restore). Key-enrollment check stays. Docs mirror sanitizes script-like HTML.
- Daily image rebuilds 08:00 and 20:00 UTC. Docs mirror of secureblue.dev at 09:30 UTC into generated `docs/secureblue/` (gitignored).

## What the overlay does

**Strip (all flavors):** Bazaar, GNOME Software, Plasma Discover, leftover store launchers.

**Origin flavor:** also strips Trivalent. `brave-origin` RPM (`/opt/brave.com/brave-origin/brave`), not `brave-browser`. Fat SELinux `brave_t` (`unconfined_domain`) + CIL userns allow-list. `harden_userns` stays on. SUID stripped on Origin. Default browser.

**Trivalent flavor (`*-trivalent`):** keep stock Trivalent + `trivalent-selinux`. No `brave_t`. Extra Chromium managed policies in `/etc/trivalent/policies/managed/` plus `trivalent.conf.d` flags. Same house locks as Origin.

**Browserless:** strips Trivalent. Nothing put back. No `brave_t`. Flatpak mask + rpm exclude until `ujust set-allow-browsers on ALLOW` (seatbelt: toolbox/brew/AppImage/`--disableexcludes` still work).

**Policies** (Origin + Trivalent, default on, each reversible):

- hardening — HTTPS, no metrics/sync/autofill/passwords/translate/WebRTC IP leak
- devices — camera/mic/geo/USB/BT/serial/HID/FS API
- jitless — `DefaultJavaScriptJitSetting: 2`
- extensions — blocklist `*`
- isolation — Disable3DAPIs, SitePerProcess, OriginKeyedProcessesEnabled (+ WebGPU flag)
- sandbox — AudioSandboxEnabled, ScreenCaptureAllowed false, DefaultJavaScriptOptimizerSetting 2

**Trivalent-only extras (default on):**

- network-sandbox — `FEATURES+=,NetworkServiceSandbox` (stock leaves this off; may clear cookies)
- referrers — ShowPunycodeDomains + ClearCrossOriginReferrers

**Opt-in:** `set-brave-devtools lock` (DeveloperToolsAvailability 2). Default allow.

**Flathub:** default `off` on Origin and browserless (stricter than stock verified). `ujust set-flathub verified|full|off`.

**Bluetooth:** default off (`bluetooth.service` masked + rfkill). Wi-Fi stays. `ujust set-bluetooth on`.

**toolbox/distrobox:** default off (PATH stub). podman stays. `ujust set-toolbox on`. Full `/usr/bin/toolbox` is a bypass.

**Flatpak lockdown:** default on (stock’s cuts, system + user). `ujust set-flatpak-lockdown off`.

**Bubblejail:** Origin launcher wrapper, default **on**. `ujust set-brave-bubblejail off`. Refused on Trivalent (stock FAQ: pairing is broken).

**Homebrew:** off by default (stock ships it). `ujust set-brew on`.

**Camera/mic:** uvcvideo + V4L/ALSA capture locked. Speakers stay. `ujust set-camera-mic on`.

**Admin split:** tty1 prompt before greeter creates a daily user, then wheel GUI lock. Empty name / 5 min skip. `ujust set-admin-split off` or `add NAME`.

**toolbox:** `/usr/bin/toolbox` and distrobox* replaced with wrappers at compose. Real bins in `/usr/libexec/unwoke/real-bin/`. `ujust set-toolbox on`.

**Extra daemons:** Avahi + ModemManager masked. `ujust set-extra-daemons on`. cups/geoclue already stock.

**Isolation pack:** Disable3DAPIs (WebGL), WebGPU CLI/conf.d flag, SitePerProcess, OriginKeyedProcessesEnabled. `ujust set-brave-isolation off`.

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
ujust set-brave-isolation on|off
ujust set-brave-sandbox on|off
ujust set-brave-devtools lock|allow
ujust set-brave-bubblejail on|off          # Origin
ujust set-trivalent-hardening on|off       # aliases of set-brave-*
ujust set-trivalent-network-sandbox on|off # Trivalent
ujust set-trivalent-referrers on|off       # Trivalent
ujust set-brew on|off
ujust set-camera-mic on|off
ujust set-admin-split on|off|add NAME
ujust set-bluetooth on|off
ujust set-toolbox on|off
ujust set-extra-daemons on|off
ujust set-unwoke-theme apply
ujust set-allow-browsers on ALLOW   # browserless
```

Stock `ujust` still works.

## Honest leftover gaps (cannot close as an overlay)

- Origin still has no Trivalent/Vanadium Chromium patches (use `*-trivalent` for those)
- Extra Trivalent policies are JSON/flags, not extra compiler patches
- Tight SELinux for Origin
- Hardware signing key / their SLSA for the *overlay* key
- GNOME Shell custom hex accent (named `blue` only)

## Key paths

- Recipes: `recipes/*.yml` (`common.yml` + `brave.yml` / `trivalent.yml` / `browserless.yml`)
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
9. **Trivalent flavor** (`*-trivalent`): keep stock Trivalent + SELinux; extra reversible Chromium policies + conf.d flags (JIT-less, isolation, sandbox, Network Service Sandbox, punycode/referrers). Origin and browserless still strip Trivalent. 12 GHCR images.

Image-side theme and toggles land on the **next image rebuild**, not Pages. Docs-only pushes should not rebuild images (`build.yml` paths-ignore).

## Tomorrow / next chat

- Confirm GHCR images after CI actually contain wallpaper + policy packs (`ujust unwoke-status` on a rebase). Theme and toggles are in the overlay; they are not live on an old local image until rebuild + rebase.
- Hard-refresh Pages if Brand / Changelog look cached.
- Changelog: `docs/_tools/generate-changelog.py`; output `docs/changelog/` is gitignored. Pages workflow now runs on every `main` push (`fetch-depth: 0`).
- Do not start a tight `brave_t` jail unless the owner asks again and accepts breakage.
- Origin/browserless still strip Trivalent. The dedicated `*-trivalent` flavor keeps it. Do not add a GUI store. Do not add xscreensaver. Do not Bubblejail Trivalent.
- Overlay-on-signed-stock is still the architecture. Do not fork.
- Trivalent policy dir is `/etc/trivalent/policies/managed/` (RPM `%{_sysconfdir}/trivalent/policies`). Extra flags via `/etc/trivalent/trivalent.conf.d/` (`CHROMIUM_FLAGS` / `FEATURES+=`, never `CHROMIUM_SYSTEM_FLAGS` or `--enable-features`).
