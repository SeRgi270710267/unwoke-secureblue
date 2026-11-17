# Owner steps

The repository stays public. Recipes, locks, and `cosign.pub` stay in git so the overlay can be audited. Invite-only applies to what people consume: the built images, the ISOs, and the published site.

This file does not change repository visibility, package visibility, or Pages. Those clicks are yours. Do them in this order.

## What is public, and what is not

Public: this git repository, the recipes, the overlay locks, `cosign.pub`, and the one-page notice on `github.io`.

Invite-only: the GHCR images after you delete the public packages and turn off inherited access, the ISOs on those private packages, and the full docs site on Cloudflare Access.

Anyone can still read the recipes and the `docs/` HTML in git and build an image themselves. That is the limit of a public repository. The published site and the prebuilt images are the parts a login can close.

## Cost

GitHub Actions minutes for a public repository are free. Do not make this repository private to save minutes; that would spend the Free plan's private minutes and is not the plan.

GitHub Container Registry storage and bandwidth are currently free. GitHub's billing page says they will give at least one month's notice before that changes.

Cloudflare Pages on a `pages.dev` hostname is free. Cloudflare Access (Zero Trust) is free for up to 50 users. Check the current seat price before you pass 50: <https://www.cloudflare.com/plans/zero-trust/>. A custom domain is optional. GitHub Enterprise is not required. GitHub Pages itself cannot hide a site on a free personal account.

## 1. Your own pull token

Do this before you delete any package.

1. Open <https://github.com/settings/tokens/new?scopes=read:packages&description=unwoke-pull>.
2. Expiration: 90 days. Scope: `read:packages` only. Do not check `repo`, `write:packages`, or `delete:packages`.
3. On each machine you still update, run `ujust invite-login` once this commit is installed, or run `files/system/usr/libexec/unwoke/invite_auth.py save` from a checkout with `UNWOKE_INVITE_USER` and `UNWOKE_INVITE_TOKEN` set for that one process. Do not pass the token as an argument.
4. `sudo stat -c '%a %U' /etc/ostree/auth.json` must print `600 root`. `rpm-ostree` and `bootc` read that file. It is not in the image.

## 2. Cloudflare, before any docs deploy

1. Create a free Cloudflare account and a Zero Trust team. Settings → Team name and domain. The team name is the `<team>` in `https://<team>.cloudflareaccess.com`.
2. GitHub → Settings → Developer settings → OAuth Apps → New OAuth app.
   - Homepage URL: `https://<team>.cloudflareaccess.com`
   - Callback URL: `https://<team>.cloudflareaccess.com/cdn-cgi/access/callback`
3. Zero Trust → Integrations → Identity providers → Add → GitHub. Paste the client id and secret. Finish the GitHub authorization. Test the provider.
4. Zero Trust → Settings → Authentication. Leave GitHub as the only login method. Do not enable one-time PIN. A PIN would let someone in with only an email, without the GitHub account.
5. Workers & Pages → Create → Pages → Upload. Project name: `unwoke-secureblue` (or another name you will put in `CLOUDFLARE_PAGES_PROJECT`). Do not upload the docs by hand.
6. Zero Trust → Access → Applications → Add an application → Self-hosted. One application, two public hostnames:
   - `unwoke-secureblue.pages.dev` (use your project name)
   - `*.unwoke-secureblue.pages.dev`
   The wildcard is the preview URL. Without it, a deploy hash can be fetched with no login.
7. Create an Allow policy named `unwoke-invite`. Include one email you control, for the first test. Session: 24 hours. The Monday workflow replaces this include list from the secret.
8. Copy the GitHub identity provider id (Zero Trust → Integrations → the GitHub row). That value is `CLOUDFLARE_GITHUB_IDP_ID`.

## 3. Tokens and variables

Repository → Settings → Secrets and variables → Actions.

Secrets:

| Name | What it is |
| --- | --- |
| `CLOUDFLARE_API_TOKEN` | API token, not the Global API Key. Permissions: Account → Cloudflare Pages → Edit, and Account → Access: Apps and Policies → Edit. No DNS, no Workers, no other account. |
| `CLOUDFLARE_ACCOUNT_ID` | The account id on the Workers overview. |
| `INVITE_ALLOWLIST` | One `github-login email` pair per line. The email is one GitHub shows Access after login (a verified address on that GitHub account). `#` starts a comment. This file must not be committed. |
| `GHCR_PUBLISH_TOKEN` | Classic PAT, 90 days, only `write:packages`, from <https://github.com/settings/tokens/new?scopes=write:packages>. It creates the first unlinked ISO package. It can push every package your user can write, so do not use it anywhere else. |

Variables (these are not secret; the site URL is printed on the public notice):

| Name | Example |
| --- | --- |
| `UNWOKE_SITE_URL` | `https://unwoke-secureblue.pages.dev` |
| `CLOUDFLARE_ACCESS_DOMAIN` | `unwoke-secureblue.pages.dev` |
| `CLOUDFLARE_PAGES_PROJECT` | `unwoke-secureblue` |
| `CLOUDFLARE_GITHUB_IDP_ID` | the identity provider id from step 2 |

Do not create `INVITE_ADMIN_TOKEN`. This repository stays public, so repository Administration is not how images are gated. GitHub has no API for granting Read on a personal-account container package. That click stays in the package UI.

## 4. Merge

Merge pull request 39 if it is still open, then this one. The merge starts one image bake because `build.yml` changed. Let it finish. It pushes onto the **existing public** packages. That is the last public push.

The Pages workflow deploys the one-page notice to github.io. It deploys the full docs to Cloudflare only after the Access application covers both hostnames. If the token is unset, the docs are not deployed.

## 5. Delete the public packages

A package that is already public cannot be made private. Deletion is the step that stops anonymous pull.

For every name in `.github/scripts/package-names.txt`, and any `unwoke-*-iso` package:

1. Package settings → Danger Zone → Delete this package.
2. If GitHub cites more than 5,000 downloads on a version, contact Support. You cannot delete that one yourself.
3. Do not restore it. Restore brings the public package back. If the name is reserved, wait or ask Support. Do not click Public on a new package.

Also:

```sh
gh release delete receipt --repo SeRgi270710267/unwoke-secureblue --cleanup-tag --yes
```

Actions → **iso-purge** → type `delete-iso-artifacts`. That removes old public ISO artifacts. New ISOs are not uploaded as artifacts.

## 6. Recreate the images without inherited access

Container packages can be private while this repository stays public. Visibility is separate from the repository. Access is not, until you turn inheritance off.

A package created by `GITHUB_TOKEN` from this public repository inherits the repository's readers. Everyone who can read a public repository can pull that package, even when the package page says Private. Anonymous `curl` returning 401 does not prove this is closed. Any logged-in GitHub user can still pull while inherit is on.

1. Actions → **bluebuild** → Run workflow. This creates the new packages.
2. Immediately, for each new package: Package settings → Inherited access → clear **Inherit access from repository**.
3. Manage Actions access → Add repository → `SeRgi270710267/unwoke-secureblue` → Role **Write**. Do not add any other repository. Adding this public repository under Actions access lets the bake push. It must not be combined with inherit. The docs warn that granting a public repository access to a private package can let forks pull. Keep the repository list to this one repo, role Write, and keep inherit off.
4. From a second GitHub account that is not invited, `docker pull` or the manifest request must be denied. Your own `read:packages` token must still succeed.

There is no supported API to clear inherit or to add a package reader on a personal account. The workflow cannot do step 2 for you.

## 7. Invite

Edit the `INVITE_ALLOWLIST` secret. Do not open a pull request with the names. Actions → **invite-sync** → Run workflow. It updates the Cloudflare Allow policy and prints only the count. It does not print logins or emails. A pull request cannot run it.

Then, for each login, on each package (the twelve images and, after the first ISO, each `-iso` package): Package settings → Invite people → Role **Read**. Read cannot invite anyone else and cannot change inherit. They do not become repository collaborators. The code stays public either way; collaborator status would only advertise who they are.

They accept nothing for a package role (access is immediate). They create their own classic `read:packages` token and run `ujust invite-login`. Send them `invite/ACCESS.md`. The gated site is the URL in `UNWOKE_SITE_URL`.

## 8. ISO

Do not attach an ISO to a Release or an Actions artifact. On a public repository, an artifact is downloadable by anyone with a GitHub account.

`GHCR_PUBLISH_TOKEN` creates `ghcr.io/sergi270710267/<name>-iso` without the OCI source label, so the package is not linked and starts private. The workflow refuses to create that package with `GITHUB_TOKEN`. After it exists, repeat step 6's inherit-off and Actions Write clicks for the `-iso` package. Later wraps push with `GITHUB_TOKEN` only when an anonymous pull is not 200.

The checksum file inside the package is signed with cosign (`--tlog-upload=false`). GHCR does not offer an expiring URL. Delete ISO versions you no longer want from the package's versions page. A copy someone already pulled is still theirs.

The installer still requires `/etc/ostree/auth.json` mode `600` before Anaconda.

## 9. Name, logo, and the license

`TRADEMARK.md` reserves the name **Unwoke SecureBlue** and the logo for builds that verify with `cosign.pub`. A rebuild must rebrand.

The overlay is `LicenseRef-Unwoke-SA-1.0` (`LICENSE`), including files that used to say MIT. Apache-2.0 paths in `NOTICE` were not relicensed. secureblue's live tree has Apache-2.0 and no NOTICE file. Earlier public versions were MIT. A copy already obtained under that grant keeps it.

Official images are the ones `cosign verify --key cosign.pub` accepts. The private key stays `SIGNING_SECRET`. An unverified rebase can still boot a rebuild. It will not verify as yours. GitHub will still let someone fork the public tree. The license forbids redistributing the overlay and builds that include it.

## 10. Repository settings

These are clicks. The repository stays public.

1. Settings → Code security → Secret scanning: on. Push protection: on. That blocks a commit that contains a token shape.
2. Settings → Code security → Private vulnerability reporting: on. `SECURITY.md` already points at advisories.
3. Settings → Actions → General → Fork pull request workflows: require approval for all outside collaborators. A fork pull request must not run with secrets.
4. Settings → Rules → `main-strict`. CODEOWNERS already covers `.github/`, `LICENSE`, and `TRADEMARK.md`. Do not add a required signed-commit rule while `vendor-watch` pushes unsigned commits as `github-actions[bot]`. Those pushes would start failing. Signed commits are practical for you on your own laptop. They are not practical for that bot unless you give it a signing key, which is a second secret in CI. Leave the rule off until you want that.
5. Tag rules: after the `receipt` release is deleted, add a ruleset for tags that blocks force-push and deletion except by you. Do not add it before that delete. The retire job deletes the `receipt` tag.

## 11. Forks and rehosts

Actions → **rehost-watch** runs daily. It opens one `rehost-watch` issue if this repository has forks or if GitHub lists another repository with `unwoke-secureblue` in the name. It does not delete the fork. It does not see images someone pushed to another registry under a different name. That limit is in the report.

## 12. Revoke and rotation

1. Remove their line from `INVITE_ALLOWLIST` and run **invite-sync**. The site stops accepting that email.
2. Package settings → remove their Read on every image and ISO package. The next GHCR token request fails. A bearer already issued lasts minutes. The installed system keeps the deployment it already has.
3. Tell them to delete the PAT at <https://github.com/settings/tokens>. You cannot delete their token. If you add them again, an old token they kept would work.

Rotate every 90 days: new `GHCR_PUBLISH_TOKEN` and a new Cloudflare API token, update the secrets, delete the old tokens the same day. Invitees replace their own `read:packages` token and run `ujust invite-login`.

If a token or the allowlist appears in a log or a commit, revoke it. `secret_scan` fails a pull request that contains a token shape. Do not print `INVITE_ALLOWLIST`.

## Signing

Keep cosign. `cosign.pub` stays in the public repository. Invitees check the signature with it. The key is not a pull secret. Old Rekor entries stay public. New builds do not publish `actions/attest-build-provenance`. The image builder's own transparency upload is unchanged, because turning it off can fail signature checks.
