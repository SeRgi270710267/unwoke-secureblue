# Owner steps: invite-only

This file is the order to follow. The code in this branch stops the factory from publishing. It does not change repository visibility, package visibility, or GitHub Pages. Those are clicks only you can make.

Do the steps in order. Skipping ahead leaves a public pull path open, or locks the bake out of the registry.

## What this cannot do

- A package that is already public cannot be made private again. GitHub's package settings say so. Deleting it and letting the bake create a new one is the path that works.
- A person who already pulled an image, saved an ISO, or cloned the git tree keeps that copy. Removing their login stops the next update. It does not wipe their disk.
- The MIT license on this overlay allows a person who received a copy to redistribute that copy. Invite-only is a lock on this registry and this repository. It is not a new license, and it does not cancel the Apache-2.0 notices on secureblue's files.
- Cosign's public transparency log keeps old signatures. This change does not turn that log off for image builds. Turning it off inside the pinned image builder can make signature checks fail, so it was left as the builder already does it. `cosign.pub` is the verification key. It is not a pull secret. Hiding it does not stop a pull.
- An invitee can hand someone else the layers they already downloaded, or their classic token, until you remove that login. They cannot add a collaborator. Only you can.
- GitHub personal accounts do not show who pulled a package. The check we have is: anonymous pull fails, and the collaborator list matches `invite/allowlist.txt`. Your security log is the rest.
- Container-registry storage and bandwidth are currently free, and GitHub says it will give a month's notice before charging. Actions artifacts are not free on a private repository. One ISO is about 4 GB. The Free plan includes 500 MB of Actions storage. A private ISO upload can fail or bill. Free private repositories also include 2,000 Actions minutes a month. A twelve-image bake can use a large part of that. Public repositories do not spend those minutes.
- Fine-grained personal access tokens cannot pull GitHub Packages. GitHub's current docs say Packages authentication is a classic token. The pull token is classic, scope `read:packages` only. The admin token is fine-grained and cannot pull images.

## 1. Pull token for your own machines

Do this before any package is deleted, so your PCs do not lose updates.

1. Open <https://github.com/settings/tokens/new?scopes=read:packages&description=unwoke-pull>.
2. Note: `unwoke-pull`. Expiration: 90 days. Scope: only `read:packages`. Do not check `repo`, `write:packages`, or `delete:packages`.
3. Generate the token. Store it in a password manager. Do not put it in git, an issue, a workflow, or the image.
4. On each machine you still want updated, run the helper from a checkout of this branch (root):

   ```sh
   sudo python3 files/system/usr/libexec/unwoke/invite_auth.py --selftest
   ```

   Then, once that commit is installed in the image, `ujust invite-login`. Until the new image is installed, the same Python file can write `/etc/ostree/auth.json` if you set `UNWOKE_INVITE_USER` and `UNWOKE_INVITE_TOKEN` in the environment for one `save` run and unset them after. Do not pass the token as an argument.
5. Confirm the file is mode `600` and owned by root: `sudo stat -c '%a %U' /etc/ostree/auth.json`.
6. `rpm-ostree upgrade` and `bootc upgrade` read `/etc/ostree/auth.json`, then `/run/ostree/auth.json`. No second config file. Do not copy the file into `/usr`.

## 2. Admin token (grants and revokes)

This token adds and removes Read collaborators. It must not be able to push code or images.

1. Open <https://github.com/settings/personal-access-tokens/new>.
2. Resource owner: `SeRgi270710267`. Repository access: only `unwoke-secureblue`.
3. Repository permissions: Administration, Read and write. Leave Contents, Actions, Secrets, and Packages at No access.
4. Expiration: 90 days.
5. Repository → Settings → Secrets and variables → Actions → New repository secret. Name: `INVITE_ADMIN_TOKEN`. Value: the token. Nothing else.

The first run of `invite-sync` on `main` does nothing useful until this secret exists and `invite/allowlist.txt` has a login. An empty allowlist with no secret is a no-op.

## 3. Merge

Merge pull request 39 first if it is still open. Then merge the invite-only pull request.

That merge starts one image bake, because `build.yml` changed. Let it finish. It pushes onto the **existing public** packages. That is the last public push. Do not click Public anywhere. The factory no longer does that for you.

The Pages workflow deploys `site-notice/` only. Wait until that run is green. Open the site and confirm it says invitation only and has no install instructions.

## 4. Unpublish Pages

GitHub Free cannot serve Pages from a private repository. Do this while the repository is still public, after the notice is what the site shows.

Settings → Pages → Build and deployment → Source: None. Confirm `https://sergi270710267.github.io/unwoke-secureblue/` no longer serves the old docs. Search caches may keep old text. That is outside this repository.

## 5. Forks, wiki

```sh
gh api repos/SeRgi270710267/unwoke-secureblue/forks --jq 'length'
```

That number must be `0`. A public fork keeps a public copy of the source. You cannot delete someone else's fork.

Settings → General → Features: turn Wikis off if they are on.

## 6. Make the repository private

Settings → General → Danger Zone → Change repository visibility → Private.

This hides the git tree, Actions logs, and artifacts from the public. It does **not** make an already-public package private. It does start spending Actions minutes.

## 7. Delete the public packages

For every name in `.github/scripts/package-names.txt`, and for any `unwoke-*-iso` package that exists:

1. Open the package → Package settings → Danger Zone → Delete this package.
2. If GitHub refuses because a version has more than 5,000 downloads, open a support request and ask them to delete it. You cannot do that one yourself.
3. Do not restore a deleted package. Restore brings the public package back.

Try Change visibility → Private first only if you want to see the refusal. The documented result is that a public package stays public. Deletion is the step that stops anonymous pull.

Confirm, with no login:

```sh
curl -sS -o /dev/null -w '%{http_code}\n' \
  -H 'Accept: application/vnd.oci.image.index.v1+json' \
  https://ghcr.io/v2/sergi270710267/unwoke-silverblue-trivalent/manifests/latest
```

You want `401` or `404`, not `200`. Repeat for the other names. The factory job "GHCR stays private" opens the `ghcr-private` issue while any of them still return 200.

## 8. Delete the public receipt and old ISO artifacts

If the retire job did not:

```sh
gh release delete receipt --repo SeRgi270710267/unwoke-secureblue --cleanup-tag --yes
```

Actions → **iso-purge** → Run workflow → confirm text `delete-iso-artifacts`. That deletes artifacts whose names contain `iso`. It does not delete the repository or Pages.

## 9. Bake the private packages

Actions → **bluebuild** → Run workflow. The new packages are private by default and, because the repository is now private, they inherit that repository's access. The workflow's `GITHUB_TOKEN` can push.

If the push is denied: on that package, Package settings → Manage Actions access → Add repository → `SeRgi270710267/unwoke-secureblue` → Role **Write**. Do not add any other repository. Do not turn "Inherit access from repository" on while the repository is public. A public repository's readers would be able to pull.

After the bake, the anonymous `curl` above must not return 200.

## 10. Invite

Edit `invite/allowlist.txt`. One GitHub login per line. Do not list yourself. Open a pull request and merge it yourself. `invite-sync` runs on that push to `main`, or you run it by hand: Actions → **invite-sync** → `sync`.

What it does:

- Adds each login as a repository collaborator with permission `pull` (Read).
- Downgrades a listed person who has Write or Admin back to Read.
- Removes anyone who is not you, not a bot, and not on the list.

A pull request cannot run it. The workflow input cannot name a new login. The list is the file on `main`. An invitee with Read cannot merge that file and cannot pass the owner check.

The person must accept the repository invitation. Until they do, their token cannot pull.

They create their own classic token with only `read:packages` (the same URL as step 1, on **their** account) and run `ujust invite-login` on the installed system, or type it into the ISO prompt. Give them `invite/ACCESS.md` after the repository is private. Do not send them `INVITE_ADMIN_TOKEN`.

## 11. ISO

Dispatch **iso** only after the private bake is the image you want to wrap, and only after the repository is private. While the repository is public the workflow builds the ISO and does not upload it. After it is private, the artifact is kept for 7 days. `output/SHA256SUMS.sig` is a cosign blob signature (`--tlog-upload=false`). An invitee with Read downloads it with `gh run download`. That is the authenticated, expiring link GitHub can actually issue. GitHub does not offer an S3-style presigned URL.

The live installer runs `invite-login` before Anaconda. The install fails if `/etc/ostree/auth.json` is missing or is not mode `600`. The credential is copied into the installed system. It is not written into the image in git.

## 12. Revoke

1. Delete the login from `invite/allowlist.txt` and merge.
2. `invite-sync` removes the collaborator. If you cannot wait for Actions: `gh api --method DELETE repos/SeRgi270710267/unwoke-secureblue/collaborators/THEIR_LOGIN` using your admin token.
3. Their next GHCR token request fails. A bearer they already hold lasts until its `expires_in`, which is minutes, and then `rpm-ostree` / `bootc` updates fail. The deployment already on disk keeps booting.
4. You cannot revoke their personal access token yourself. Tell them to delete it at <https://github.com/settings/tokens>. Removing their access is what stops a copied token. If you invite them again, an old token they did not revoke would work again.
5. Run **invite-sync** → `audit`. It fails if GitHub has a collaborator the file does not list, or if someone on the list is not Read.

There is no per-pull counter on a personal account. After a revoke, look at <https://github.com/settings/security-log> for `repo.remove_member` and unexpected `personal_access_token` use. A collaborator count above the allowlist is the anomaly the workflow prints.

## 13. Rotation

- Every 90 days, or the day you think `INVITE_ADMIN_TOKEN` leaked: create a new fine-grained token (step 2), update the Actions secret, then revoke the old token on the same day. Run `audit`.
- Invitees do the same with their `read:packages` token and run `ujust invite-login` again. The helper refuses a token whose `X-OAuth-Scopes` is anything except `read:packages`, and it refuses a `github_pat_` token.
- If a pull token appears in a log, an issue, or a commit: remove that login (step 12), revoke the token, and do not push the value. `secret_scan` fails the pull request if a token shape is in the diff.

## Signing

Keep cosign. Invitees verify with `cosign.pub` from the private repository:

```sh
cosign verify --key cosign.pub ghcr.io/sergi270710267/<name>
```

That proves the signature matches the key. It does not grant a pull. The key stays in the repository so invitees can check it. It is not published on the public site or the receipt release. Old Rekor entries and old GitHub attestations, if any were already public, stay public. New builds do not run `actions/attest-build-provenance`.
