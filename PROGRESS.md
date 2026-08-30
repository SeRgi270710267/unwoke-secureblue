# Unwoke SecureBlue — development handoff

**Read this first** if continuing in a new chat (including another computer). Working tree was clean and pushed when this file was last committed.

- Branch: `main`, synced to `origin/main`.
- GitHub: `SeRgi270710267/unwoke-secureblue`
- Clone anywhere: `git clone https://github.com/SeRgi270710267/unwoke-secureblue.git` then `git pull`.
- **Pickup phrase:** continuing Unwoke SecureBlue from `PROGRESS.md` on `main`.
- Site: https://sergi270710267.github.io/unwoke-secureblue/
- Privacy sell page: https://sergi270710267.github.io/unwoke-secureblue/privacy/
- Factory: https://sergi270710267.github.io/unwoke-secureblue/factory/
- Workarounds: https://sergi270710267.github.io/unwoke-secureblue/stock-issues/
- Fingerprint tutorial: https://sergi270710267.github.io/unwoke-secureblue/tutorials/fingerprint/
- Changelog: https://sergi270710267.github.io/unwoke-secureblue/changelog/ (generated; gitignored)
- **Handoff commit:** whatever `git log -1 --oneline` is after this file is pushed (this write is the close-chat save). Previous session HEAD before this file: `e7494a7` (never sqlite3 .recover a full Origin RPM index).
- **GitHub ruleset:** only **`main-strict`**, Active, target `refs/heads/main`. Requires PR + 1 approval + Code Owners + status **`Strict PR gate`** (GitHub Actions). Block force-push + deletion. **Repository admin bypass** so the owner (and this agent) can still `git push` to `main`. No `protect-main`. No auto-merge. Grok cannot merge.

**How to resume:** clone the repo (or open it), say you are continuing Unwoke SecureBlue from `PROGRESS.md`. Do not rebuild images for docs-only work. Do not docker-pull Atomic images (layer depth). Do not auto-accept a new `cosign.pub` or auto-exec live `/usr/libexec/secureblue/*.py`.

**Not affiliated with secureblue.** Overlay on their signed Fedora Atomic images. Not a fork.

## Product name

Display: **Unwoke SecureBlue** (`Unwoke` = modifier; `SecureBlue` = one word, S+B). Slugs stay lowercase (`unwoke-secureblue`, `unwoke-silverblue`).

## Architecture (do not change without a reason)

- BlueBuild overlay on official signed secureblue images.
- Twelve GHCR images: silverblue / kinoite × nvidia-open × (Origin | trivalent | browserless).
- `ghcr.io/sergi270710267/<name>:latest`. Cosign with a GitHub Actions secret (not a hardware key).
- First rebase is `ostree-unverified-registry`; first-boot promotes `ostree-image-signed`.
- Image CI: `.github/workflows/build.yml` (paths-ignore docs). `cancel-in-progress: false` so a later overlay push queues instead of killing a bake. Pages: `.github/workflows/pages.yml` from `docs/`.
- Base canary: `.github/scripts/scan-base-canary.sh` runs on the four official bases *before* the 12-image matrix. `cosign verify` + `crane export` (never docker/podman pull — Atomic images exceed Docker layer depth; never run the image) for needles in `.github/scripts/base-canary-needles.txt`. Hit = no overlay. Does not catch a generic backdoor or obfuscation. Stock still cannot push to this GitHub/GHCR; user machines follow Unwoke GHCR after signed rebase. Canary matrix `fail-fast: false` so all four bases still report if one is red.
- Automatic snapshot refresh: `.github/scripts/auto-refresh-snapshots.sh` on main. If stock `harden_flatpak.py` / `flatpak.just` change and pass a targeting scan, CI commits snapshots and regenerates `flatpak-lockdown-lists.sh`. Overlay is not blocked. Runtime still uses Unwoke scripts. Poison (file names Unwoke) is not auto-copied.
- Stock `ujust harden-flatpak` hits `/usr/libexec/secureblue/harden_flatpak.py`, which is an Unwoke trampoline (`os.execv` to `/usr/libexec/unwoke/harden-flatpak.sh`). Compose fails if that trampoline is missing. Inspect also checks it.
- Post-publish inspect: after each non-PR BlueBuild, **before** `attest-build-provenance`. `.github/scripts/inspect-flavor.sh` crane-exports GHCR `:latest`. Cosign must use classic `.sig` tags (`COSIGN_OCI_EXPERIMENTAL=0`, `--new-bundle-format=false` if the flag exists) — GitHub certificate attestations otherwise fail with `expected key signature, not certificate`. Flavor ELF checks use tar member types (file/symlink/hardlink), not leftover empty dirs. Origin ELF is often a hardlink. Twice-daily `verify.yml` is schedule + dispatch only (`pick` job builds the matrix — same `matrix`-in-`if` rule as `iso.yml`). Do not add `on: push`. Does not auto-accept a new `cosign.pub`.
- Auto-public GHCR: after BlueBuild (success or failure of the matrix) **and** after ISO wrap, `.github/scripts/public-packages.sh` tries to set `unwoke-*` (and `*-iso`) container packages Public so anonymous rebase/USB fetch works. **Warn-only** — never fails the bake. `GITHUB_TOKEN` often cannot flip visibility; the log then prints the Packages settings URL. One manual Public click is enough after that.
- Extract helper: `.github/scripts/extract-prefixes.py` (stream tar; `extractfile()` only on regular files; copy hardlinks if the target is already extracted). Crane for canary/inspect is checksum-pinned `v0.20.3` in `install-crane.sh`.
- Factory alarms (one reused issue per lane, not auto-merge): `factory-alarm` (canary/watch/bake/inspect), `iso-alarm` (USB wrap), `pages-alarm` (site), `vendor-installers` (contracts after allowlisted heal), `receipt-alarm` (moving GitHub Release `receipt`). Shared opener: `.github/scripts/issue-alarm.sh`. A canary hit, new `keys/secureblue.pub`, new vendor hostname, Flathub, `gpgcheck=0`, or titanoboa pin bump is **not** auto-merged. Map: `docs/factory/`.
- GitHub Release tag `receipt` is a verification pack only (`docs/_tools/publish-receipt.sh` on full `verify.yml` **and** after overlay `bluebuild`). Assets: `cosign.pub` + `DIGESTS.txt` (crane digest + Unwoke cosign, no docker pull). After ISO wrap, tiny `SHA256SUMS` / `.sig` only. One moving tag, rewritten in place. Never the ISO (2 GiB cap). Never fails inspect/bake (script always exits 0). 0 verified images → leave last good receipt + alarm. Partial list → publish what verified + alarm. Next full green closes. Ignore GitHub’s source zip.
- ISO `oras push` retries **once** on flake (same titanoboa pin, no bump). `continue-on-error` still so a GHCR publish miss cannot fail the wrap artifact.
- `remove-trivalent.sh` (Origin + browserless): `dnf remove` then `rm` leftover `/usr/bin/trivalent` and `/usr/lib64/trivalent`. Inspect fails if those remain.
- Stock MOTD replaced (`usr/libexec/secureblue-motd`). User nags masked by default: deprecation notice, update-verification, flatpak-setup (`ujust set-stock-nags on` to restore). Key-enrollment check stays. Docs mirror sanitizes script-like HTML.
- Daily image rebuilds 08:00 and 20:00 UTC. Docs mirror of secureblue.dev at 09:30 UTC into generated `docs/secureblue/` (gitignored).
- Empty-disk ISO: `.github/workflows/iso.yml` wraps a published Unwoke GHCR image. **Do not use `ublue-os/titanoboa@main`** — that old LiveCD requires `/usr/lib/bootc-image-builder/iso.yaml` in the OS image. Pin is `ublue-os/titanoboa@840217d` plus `.github/workflows/isos/prep_{rootfs,initramfs}.sh` (Anaconda live). RoyalOughtness hard-codes their keys — skip it. **Do not auto-bump the pin.** Live USB is Anaconda; installed OS is the GHCR image. Enroll **their** Secure Boot key. A `pick` job builds the matrix (dispatch = one image; weekly = four Trivalent desktops). **Do not put `matrix` in a job-level `if`**. Weekly Sunday 10:00 UTC. Artifact 14 days + GHCR `-iso`. `iso-alarm` if wrap fails; `public-packages.sh` after. Does not block the overlay factory.
- Vendor list is `files/system/usr/share/unwoke/vendor-installers.json`. `vendor.py schema` requires known kinds, allowlisted HTTPS, `yum-repo` + `require_gpgcheck: true`. Heal may rewrite URLs on `HOSTS` only (not add hosts). Compose generates a `.desktop` and a missing offline-help stub per key; inspect fails the bake if those are missing. Tutorials hub regenerates at Pages and on vendor-watch. New app = JSON stanza. New hostname = human edit of `HOSTS`.
- **Public mark (always, do not wait to be asked):** new overlay files under `files/` and `recipes/` get `UNWOKE-SHIPPED-FIRST` + MIT copyright. Compose runs `mark-check.py --apply` so a forgotten file is stamped in the image. Inspect and the PR gate check only. Live Chromium/Brave/Trivalent `policies/managed/*.json` must **not** contain the token (`--install-policy` strips it). That keeps chrome://policy as the real locks and does not add a unique unrecognized policy. No phone-home. No obfuscation. License stays MIT. Do not weaken SELinux / USBGuard / Safe Browsing / fwupd to “protect credit.”

## What the overlay does

**Strip (all flavors):** Bazaar, GNOME Software, Plasma Discover, leftover store launchers.

**Origin flavor (unsuffixed GHCR names):** also strips Trivalent. `brave-origin` RPM (`/opt/brave.com/brave-origin/brave`), not `brave-browser`. Fat SELinux `brave_t` (`unconfined_domain`) + CIL userns allow-list. `harden_userns` stays on. SUID stripped on Origin. Not the recommended default.

**Recommended default:** `*-trivalent` (stock Trivalent jail + extra reversible policies). Install picker, README rebase, weekly ISO. Origin remains a named choice.

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

**Flatpak lockdown:** default on (stock’s cuts plus extra xdg/host-root, not host-os). `ujust set-flatpak-lockdown off`.

**Flatpak record:** Pulse + PipeWire capture blocked for Flatpaks, independent of lockdown. `ujust set-flatpak-record off`.

**NFS/CIFS clients:** modules blacklisted. Stock only masks nfs-server; we never unmask the server. `ujust set-network-fs on`.

**USB encrypt-on:** Anaconda `autopart --encrypted` + Argon2id 2 GiB (`/etc/cryptsetup.conf` on the live ISO and `/usr/etc/cryptsetup.conf` on the OS). Untick Encrypt if you must.

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
ujust setup
ujust why
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
ujust set-flatpak-record on|off
ujust set-network-fs on|off
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
9. **Trivalent flavor** (`*-trivalent`): keep stock Trivalent + SELinux; extra reversible Chromium policies + conf.d flags. Origin and browserless still strip Trivalent. 12 GHCR images.
10. Hostile-upstream canary (crane, not docker) + snapshot auto-refresh + harden-flatpak trampoline + MOTD/nags mask.
11. Factory autos that do not drop security: post-publish inspect, twice-daily verify.yml, one `factory-alarm` issue. Key rotation / canary hits stay manual.
12. **Direct USB ISO** (`iso.yml`): Titanoboa wrap of published Unwoke image. Dispatch any of 12. Weekly Sunday 10:00 UTC the four Trivalent desktops → `ghcr.io/sergi270710267/<name>-iso:latest` (oras + cosign). Artifacts 14 days. Does not block overlay.
13. **This PC pickup (2026-08-29):** cloned/pulled `29be70c`. Dispatch of `iso` failed on `matrix` in job `if`, then the wrap failed because old titanoboa wanted `iso.yaml`. Switched to RoyalOughtness/titanoboa + Anaconda live hooks.
14. **First-session setup (no lock loosened):** `ujust setup` / autostart window. Reboot nag when `/etc/unwoke/signed-staged` exists. Install page is three questions, not twelve names. Overlay bake required for the window; Pages for the picker.
15. **Guided recovery + factory public packages (ISO still separate):** `ujust why` / setup option 3 maps “broken” to the matching lock (does not auto-unlock). Option 4 runs leftover stock `ujust` (Secure Boot key, kargs, USBGuard) on confirm. After a green overlay bake, `public-packages.sh` tries to set GHCR packages Public (warn-only; does not fail the bake). Install page queries GitHub for a last-green USB ISO and says so if none exists.
16. **Tutorials tab (Pages):** everyday tasks with the secure path first (first hour, apps without a store, Bluetooth, camera, USBGuard, updates/rollback, daily user, VPN DNS, toolbox, health check). Does not auto-unlock. Docs-only — no overlay bake.
17. **Desktop UX without loosening locks:** GTK **Unwoke setup** window (app grid + autostart; TUI fallback). Same stamps as `ujust`. Tutorial buttons. Repeating signed-reboot nag (login + 15 min timer) until `/etc/unwoke/signed-staged` is gone. Daily-user still **before the greeter** (dialog installer screen, not wheel-on-GDM-first). Install page: Windows/Linux/macOS order, copy buttons, USB download CTA when a green bake exists.
18. **Compared tab (Pages):** living list vs stock — easy words, stricter table, easier table, factory, where stock still wins, dated ledger. Update this page when we ship a lock or a UX win. Does not auto-unlock. Docs-only.
19. **Recommended default is Trivalent:** install picker, README, weekly ISO four `*-trivalent` desktops. Unsuffixed GHCR names stay Origin. Origin radio shows a warning. No lock loosened.
20. **Search + undo + offline help:** `.desktop` launchers so GNOME/KDE search hits Bluetooth/camera/Flathub/sites/USB. Setup **You loosened** / `ujust loosened` puts locks back. Tutorials copied to `/usr/share/unwoke/help/` (`open-tutorial.sh` prefers local). Overlay bake required. No auto-unlock.
21. **Last-green stamp + Reboot on the nag:** Pages writes `status.json` (bake + inspect + ISO if green). Home/Install/Images/Compared show it. `notify-reboot.sh` adds a Reboot button when libnotify supports `--action`; timer waits up to 180s. Overlay bake for the button. No lock loosened.
22. **Proton.me wizard (no store):** `ujust install-proton` / Setup → Proton.me. Trivalent first; VPN WireGuard; official Mail/Pass RPM only after SHA512 + asked `set-unconfined-userns`. No unverified Flathub. Tutorial + Compared. Overlay bake required.
23. **IVPN wizard (no store):** `ujust install-ivpn`. WireGuard import first. Official Fedora repo + `ivpn`/`ivpn-ui` only after you accept an extra RPM origin. No Snap. Tutorial + Compared. Overlay bake required.
24. **Vendor installer watch:** live SHA512; heal also covers redirects, field renames, sidecar checksums, www, repo path, retries on 429/5xx (no rewrite). Allowlisted HTTPS + checksum/gpg only. Flathub/HTTP still a human issue.
25. **Every vendors{} key is first-class:** `install-vendor.sh`, Setup tab Strict apps, generated `.desktop` files, inspect JSON, CI check/heal. New app = JSON stanza, not a Proton/IVPN-only fork of the watch.
26. **Mullvad VPN** on that list: WireGuard first; official `mullvad.repo` + `mullvad-vpn` asked. Hosts allowlisted for heal. Not Mullvad Browser. Tutorial + `ujust install-mullvad`.
27. **Tutorials hub generated at Pages deploy** from `tutorials-core.json` + every `vendors{}` `tutorial` slug. Vendor command lists injected. Missing slugs get a stub page. Does not auto-unlock.
28. **Whole-factory self-heal (no weaker locks):** ISO + Pages alarm issues; public-packages after ISO; compose chmod-all + vendor help stubs; inspect every JSON key; vendor schema/allowlist including `mail.proton.me` / `pass.proton.me`; vendor-watch regenerates tutorials hub; site [Factory](https://sergi270710267.github.io/unwoke-secureblue/factory/) map of auto vs human. Canary, signing key, new vendor host, Flathub, titanoboa pin stay human.
29. **Sit-back nags without auto-trust:** twice-daily `watch-trust.sh` (on `verify.yml`, does not bake) opens `stock-key` / `titanoboa-pin` / `ghcr-private` instead of a silent log line. Tries Public again. Relocates 404 stock snapshot URLs only inside `secureblue/live` + unique filename. Does **not** replace `keys/secureblue.pub` or bump titanoboa. Pin check uses the GitHub commit object (`docs/_tools/titanoboa-pin.py`), not `git ls-remote URL SHA`. GHCR alarm uses anonymous OCI pull so already-public OS images do not keep `ghcr-private` open.
30. **Site copy + stock mirror:** home no longer says we only change browser+store; Images no longer claim every GHCR name is already Public; ISO size ~4 GB; USB baker is green. Mirror: stock install form is replaced with a pointer (we do not run it), Images/Reporting mirrored with banners, hub grouped, FAQ/Features/Install notices so stock Bazaar/Flathub text cannot be mistaken for Unwoke. Same-page stock anchors (`#releases`, TOC, skip link) stay on the mirrored page — `<base href>` used to dump them on our homepage. Heading ids from `{: #id}` are kept. `https://secureblue.dev/…` links rewrite to the local mirror when we have that page.
31. **People-facing progress is generated:** Pages runs `docs/_tools/generate-progress.py` into Home, Compared ledger, Changelog highlights. Optional commit trailers `People:` / `Vs:` / `Where:`. Factory-only git omitted. Seed: `people-seed.json`. Do not hand-edit the Compared table for ordinary work. Features toggles stay a written spec.
32. **Mirrored stock snippets that differ here get an Unwoke box:** JSON map in `docs/_tools/stock-unwoke-cmds.json`. New stock `set-foo-modules` / `set-foo-unfiltered` auto-pairs to overlay `set-foo` if that recipe exists. Unknown risky names get `ujust why` plus `mirror-cmds` issue. Known-same (enroll key, kargs, USBGuard) left alone. Does not auto-unlock.
33. **Workarounds page:** Pages scans open secureblue issues, keeps only those that can hit this overlay and map to an allowlisted revertable `ujust`. Never baked into GHCR. Never suggests setenforce 0. PRs/CI/other flavors omitted.
34. **Privacy vs stock (no security cut):** default-off Fedora countme, NM connectivity-check, DHCP hostname/DUID (RFC 7844-ish + IPv6 stable-privacy), GNOME/Dolphin thumbnails. Hyperlink ping off in hardening pack (prefetch already off). Boot `privacy.sh apply-boot` remasks. Inspect checks files. Revert: `ujust set-countme|set-connectivity-check|set-dhcp-hostname|set-thumbnails on`. Not fwupd, not Safe Browsing.
35. **Fingerprinting vs locks:** security-first defaults stay. Tutorial + FAQ + Setup (`i` / GUI button) explain which packs make you rarer than stock Trivalent vs phone-home that sites never see. Blend is opt-in, one pack, not a silent default.
36. **More privacy defaults that are still locks:** Privacy Sandbox / Cast / Chrome time-query off (Safe Browsing stays), LLMNR+mDNS registration off, systemd-resolved LLMNR=no (mDNS back if Avahi allowed), GNOME remember-app-usage off, IPv6 ip6-privacy=2. Hardening-off and JIT/WebGL/devices-off print a WARN. Not Safe Browsing off, not fwupd off.
37. **Fingerprinting honesty:** we ship security-first extra browser packs (rarer than stock Trivalent). Phone-home off does **not** fingerprint websites. Blend is opt-in, one pack, warned. Tutorial + Setup `i` / GUI button. Do not drop JIT/WebGL by default to “look like Chrome.”
38. **Privacy sell page** (`docs/privacy/`): four stories + full table vs stock. Nav **Privacy**. Home + Compared link here.
39. **Workarounds page:** keyword map to allowlisted `ujust` only (tightened: skip `[FEAT]`, ARM, MTP≠USBGuard, vsock≠Xwayland). Optional Pollinations batch for an “AI note”; often 402 — then dashed **Keyword only** panel. Cards: blue AI strip vs Type this box. Never baked.
40. **Contributor door:** `CODEOWNERS` = `@SeRgi270710267`. `pr-gate.yml` job name **`Strict PR gate`**. PR/issue templates, `CONTRIBUTING.md`, `SECURITY.md`. GitHub ruleset **`main-strict`** only (no `protect-main`). Maintainer merge only. No auto-merge. `pull_request_target` forbidden. Owner bypass so agent can still push `main`.
41. **False titanoboa-pin + named GHCR leftover:** #5 was `git ls-remote` missing tag v0.2 (`840217d` still there). Checker now asks GitHub for the commit. All twelve OS GHCR images already pull anonymously.
42. **#6 settings URL 404:** `unwoke-silverblue-trivalent-iso` was never on GHCR. Run 20 `oras push` died: absolute file path. USB is the Actions artifact. Do not invent `/users/.../packages/container/NAME/settings` (500 even for public OS). oras now pushes from the ISO dir with a relative name. Do not auto-bump titanoboa.
43. **Receipt release:** one moving GitHub tag `receipt` (pubkey + verified digests). Hands-off rewrite on full verify **and** after overlay bake. Tiny USB checksums after wrap. `receipt-alarm` if it cannot write; last good files stay. Not the OS, not the USB.
44. **Babysit less:** overlay `cancel-in-progress: false`. ISO oras one retry, same pin. No extra secrets. No auto-trust.
45. **Stock FEAT we shipped, stock did not:** USB encrypt-on + Argon2 2 GiB (ISO kickstart + `/usr/etc/cryptsetup.conf`); Flatpak record-block (independent of lockdown, actually re-allows on off); extra xdg/host-root lockdown (never host-os); NFS/CIFS *clients* blacklisted while nfs-server stays masked; `audit-unwoke` warns on Flatpak browsers. All reversible except LUKS after you chose it at install. Compared page is the public scoreboard.
46. **After you log in:** `docs/start/` is the first-session walkthrough (Unwoke setup, not GNOME Settings). First-hour tutorial is the offline copy. Nav **After login**. Install/Home/Post-install/FAQ point here. Setup window button still opens `first-hour`.
47. **Shipped first:** `docs/ahead/` tracks official secureblue GitHub FEATs we shipped first. Tickets never drop. Open = still ahead. When they close after us, the card moves and `stock-feats` opens so a human reviews their PR. If theirs is better: `adopted.on` / `note` / `commit` in `stock-feats.json`. If ours stays: `stock_reviewed: keep`. Never auto-copy.
48. **More stock FEATs shipped:** audit session-bus (#887); ISO NTS not fedora NTP (#1185); DHCP release+IAID (#1569); Mozilla CA trim (#1606); noexec /dev/shm+/tmp (#697); SHSTK/IBT on (#1295); /boot 700 (#391). Reverts: `set-ramdisk-exec`, `set-cet`, `set-boot-perm`, `set-extra-cas`, `set-dhcp-hostname`. Did not ship malloc-light, lockdown-lite, thunderbolt-on, YubiKey-required, unattended fwupd.
49. **Public mark:** `/usr/share/unwoke/SHIPPED-FIRST.txt` token `UNWOKE-SHIPPED-FIRST` (also on the site and the signed `receipt` release). Every overlay script/unit carries the same token + MIT copyright. Compose and inspect fail if a new script is unmarked. Copy-paste is grep-able. Ideas on their tracker stay public; MIT notice must travel with code.
50. **Mark is a default-on lock:** every overlay source (scripts, units, share JSON, desktops, recipes, generated ramdisk/CA drop-ins) carries `UNWOKE-SHIPPED-FIRST`. `/usr/share/unwoke/NOTICE` + MIT `LICENSE`. `mark-check.py` at compose, inspect, and PR gate. `ujust audit-unwoke` fails if the ledger is gone. Live browser managed policies do **not** get that string. No obfuscation. License stays MIT. No ujust to strip it.
51. **Mark is automatic and must not cut privacy/security:** compose `--apply` stamps unmarked overlay files. Live browser `policies/managed` is scrubbed (`UnwokeShippedFirst` stays only on share/ sources, vendors, wallpaper metadata). Inspect fails if the token leaks into managed policy JSON. `ujust` copies use `--install-policy`. No phone-home. Real policy keys unchanged.
52. **Origin USB wrap (still open at close-chat):** extra Origin dnf (Brave RPM + `selinux-policy-devel` install/remove) leaves `rpm -q` unusable. Titanoboa `initramfs` then dies. Trivalent + browserless USB wraps are green. Do **not** bump titanoboa. `#7` closed because a later Trivalent wrap was green — reused iso-alarm names the image now. iso-alarm `IMAGE_HINT` is in `iso.yml` + `issue-alarm.sh`.
53. **What we already learned (do not repeat):** `rpm --rebuilddb` in ostree compose fails; in the live rootfs it “succeeds” by emptying the index (`kernel-core is not installed`). `PRAGMA integrity_check` is a false bake fail on RPM sqlite. Inspect must **not** fail on `-shm`; only a non-empty `-wal`. `sqlite3 .recover` of Origin’s **95 MiB** restored db wrote a **4.3 MiB stub**; live `dnf` then installed 100–189 packages and `rootfs-selinux-fix` died on unlabeled `rpc_pipefs`. Never recover a large db.
54. **Overlay now:** `apply-unwoke.sh` **checkpoints WAL first**, drops sidecars, then saves `/usr/share/unwoke/.rpmdb-pre-flavor.sqlite` (sqlite only). Origin `rebuild-rpmdb.sh` drops live Origin WAL, restores that sqlite after Brave dnf, deletes the bak. Do **not** copy sqlite onto leftover WAL. `common.yml` ships `sqlite` CLI. Inspect checks no WAL. WAL-set bake [33305148886](https://github.com/SeRgi270710267/unwoke-secureblue/actions/runs/33305148886) (`83a8dec`) green on compose, **red on Origin USB**.
55. **ISO hook now** (`.github/workflows/isos/prep_initramfs.sh`, paths-ignore, no overlay bake): squashfs override; if `rpm -q kernel-core` already works, write `/etc/dnf/vars/releasever` and stop. If the sqlite is **≥20 MiB**, skip recover; `dnf5 download kernel-core-$krel` + `rpm --justdb --nodeps -ivh` so titanoboa’s queryformat works. Recover only a small/stub db. If kernel-core is still missing after justdb, **exit 1** — do not hand a malformed db to titanoboa dnf. Do **not** `dnf install dracut-live` in the hook.
56. **ISO wrap 33304494809 (Origin silverblue, hook `e7494a7`, image `6f22bd9`) FAILED.** Hook: same 95 MiB sqlite, skipped recover, `rpm -q kernel-core` failed (`SELECT ... FROM 'Name'`: database disk image is malformed), justdb died the same way, titanoboa `dnf install -y dracut-live` pulled **177** packages and died on OpenPGP. Root cause: restore copied pre-flavor sqlite on top of Origin extra-dnf WAL, then python checkpoint mixed them. Trivalent never extra-dnfs Brave so its WAL still matches.

**Next Origin USB test:** do **not** restore/checkpoint another sqlite copy. Hook [33306910391](https://github.com/SeRgi270710267/unwoke-secureblue/actions/runs/33306910391) on checkpoint-before-save bake `b1cb805` still failed the same way (95 MiB malformed `Name` table). Next overlay: **stop Origin extra dnf** — prebuilt `unwoke_brave.pp` + rpm2cpio/cpio extract of `brave-origin` so Packages stays Trivalent-shaped. Then dispatch `unwoke-silverblue`.

57. **ISO wrap 33305773882 (Origin silverblue, overlay `83a8dec`) FAILED in the hook.** Same 95 MiB malformed sqlite (`SELECT ... FROM 'Name'`). WAL-set restore did not help — the **saved** copy was already torn. Fail-fast worked (no 177-package titanoboa dnf).
58. **ISO wrap 33306910391 (Origin silverblue, overlay `b1cb805` checkpoint-before-save) FAILED in the hook.** Same 95 MiB, same `Name` malformed, justdb died, hook `exit 1`. Restoring any ostree sqlite copy does **not** make `rpm -q kernel-core` work on Origin. Stop that loop.

**This overlay (landed, Origin USB still red):** checkpoint-before-save in `apply-unwoke.sh`; skip `.sqlite` / `.rpmdb-pre-flavor*` in `mark-check.py`. **Next overlay (required):** skip Origin extra dnf — prebuilt `.pp` / CIL, install Brave files without `dnf` mutating Packages.

Image-side theme, privacy.sh, Setup fingerprint button, rpmdb restore, and sqlite CLI land on the **image rebuild**, not Pages. `iso.yml` / `issue-alarm.sh` / `isos/**` are in `build.yml` paths-ignore. Overlay scripts (`rebuild-rpmdb.sh`, `apply-unwoke.sh`, `inspect-flavor.sh`) **do** bake.

## Tomorrow / next chat

- Pickup: *continuing Unwoke SecureBlue from `PROGRESS.md` on `main`.* Other PC: `git clone https://github.com/SeRgi270710267/unwoke-secureblue.git` then `git pull`. Phrase: continuing Unwoke SecureBlue from `PROGRESS.md`.
- Close-chat HEAD after this file is pushed: `git log -1 --oneline`. Product overlay in GHCR `:latest` is checkpoint-before-save bake `b1cb805` / run [33306351364](https://github.com/SeRgi270710267/unwoke-secureblue/actions/runs/33306351364). Origin USB still red.
- **In flight:** none. Do not dispatch Origin ISO again until Origin extra dnf is gone. Trivalent/browserless USB still green.
- USB: **8 green** (all Trivalent + all browserless). Origin still red.
  - green: [silverblue-trivalent](https://github.com/SeRgi270710267/unwoke-secureblue/actions/runs/33271596640) [kinoite-trivalent](https://github.com/SeRgi270710267/unwoke-secureblue/actions/runs/33271598181) [silverblue-nvidia-open-trivalent](https://github.com/SeRgi270710267/unwoke-secureblue/actions/runs/33271599868) [kinoite-nvidia-open-trivalent](https://github.com/SeRgi270710267/unwoke-secureblue/actions/runs/33271601020) [silverblue-browserless](https://github.com/SeRgi270710267/unwoke-secureblue/actions/runs/33271607795) [silverblue-nvidia-open-browserless](https://github.com/SeRgi270710267/unwoke-secureblue/actions/runs/33271608871) [kinoite-browserless](https://github.com/SeRgi270710267/unwoke-secureblue/actions/runs/33271610062) [kinoite-nvidia-open-browserless](https://github.com/SeRgi270710267/unwoke-secureblue/actions/runs/33271611064)
- Recommended USB today: `unwoke-silverblue-trivalent` Actions artifact. Not Ventoy. Enroll **their** Secure Boot key. Weekly still four Trivalent.
- Public mark is automatic (`mark-check.py --apply` at compose). Do not put `UNWOKE-SHIPPED-FIRST` into live Chromium/Brave/Trivalent `policies/managed`. Do not weaken privacy/security for credit. Do not stamp `.rpmdb-pre-flavor.sqlite`.
- Confirm on a real USB/rebase: `ujust setup` / `ujust audit-unwoke` / `ujust set-countme` status off / `ujust why`. Shipped first: https://sergi270710267.github.io/unwoke-secureblue/ahead/
- **#5** was a false alarm (pin still `840217d` / tag v0.2). Do not bump.
- First stranger PR: confirm **Strict PR gate** runs; if the merge box cannot find the check, edit `main-strict` and pick it from search after that run.
- Do not add `on: push` to `iso.yml` or `verify.yml`.
- Do not start a tight `brave_t` jail unless the owner asks again and accepts breakage.
- Do not add a GUI store. Do not Bubblejail Trivalent. Do not fork. Do not default-off Safe Browsing or fwupd.
- Overlay-on-signed-stock. Trivalent policy dir `/etc/trivalent/policies/managed/`. Flags via `trivalent.conf.d`.
- Canary/inspect: never `docker pull` Atomic images. Crane + `extract-prefixes.py`. Bake [33300308115](https://github.com/SeRgi270710267/unwoke-secureblue/actions/runs/33300308115) attempt 1 failed `cosign verify` exit 10 on stock `silverblue-nvidia-open-hardened` in 2s (flake, not a needle). Attempt 2 green. Rerun failed canary; do not skip it.
- Do not auto-merge canary hits, a new `keys/secureblue.pub`, a new vendor hostname, Flathub, `gpgcheck=0`, or a titanoboa pin bump.
- Do **not** `rpm --rebuilddb` to “fix” Origin (empties the index). Do **not** `sqlite3 .recover` a ~90 MiB rpmdb.
