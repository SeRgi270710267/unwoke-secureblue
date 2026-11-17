# Security

This overlay sits on [secureblue](https://secureblue.dev). Kernel, SELinux policy they ship, Trivalent-the-browser, and USBGuard in stock — report those **upstream**, not here.

## Reporting a vulnerability

Do not file a public issue, pull request, or discussion for a live remote exploit in the overlay, our scripts, or our GHCR images.

Use a [private GitHub security advisory](https://github.com/SeRgi270710267/unwoke-secureblue/security/advisories/new). Only the maintainer can see it.

Include what you found, where (file, image, or `ujust` command), how to reproduce it, and what an attacker could do with it. Do not include `SIGNING_SECRET`, `cosign.key`, tokens, or someone else's data. Use made-up values.

We aim to acknowledge a report within 7 days and to say what we plan to do within 30 days. Give us a reasonable time to fix it before you talk about it publicly. We will credit you in the fix if you want.

## Scope

In scope:

- This repository's overlay (`files/`, `recipes/`), GitHub Actions workflows, and the images we publish at `ghcr.io/sergi270710267/unwoke-*`.
- The site published from `docs/`.
- Signing and verification of **our** images (`cosign.pub` in this repo).

Out of scope: stock secureblue kernel, their SELinux policy, Trivalent-the-browser, USBGuard as they ship it, denial of service against GitHub or GHCR, and findings that need a machine that is already compromised.

## Rules for testing

- Test your own machine or a local VM. Do not attack someone else's install.
- Do not run scanners against the GitHub Pages site or GHCR.
- Stop when you see data that is not yours.

## Secrets

`SIGNING_SECRET` / `cosign.key` live only as the GitHub Actions secret `SIGNING_SECRET`. Optional model keys (`XAI_API_KEY`, `GROQ_API_KEY`, `UNWOKE_AI_KEY`) are secrets too. They do not belong in the tree, in issues, or in chat.

We will not merge a change that sets `gpgcheck=0`, `setenforce 0`, or an unsigned rebase as a default.

If you think a secret was committed, report it privately. Do not copy the value anywhere.
