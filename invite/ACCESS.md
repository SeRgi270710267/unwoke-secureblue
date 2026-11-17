# Invitee access

The owner sends you this after the repository is private. You cannot invite anyone else. Read on the repository does not include Administration, and the sync workflow refuses every actor except the owner.

## What you get

- Read access to this repository, after you accept the invitation email.
- Pull access to the private images, because the packages inherit that Read access.
- A classic personal access token that only you create, with only the `read:packages` scope.

You do not get the signing private key, the admin token, or a way to add a collaborator.

## Token

On your GitHub account, not the owner's:

<https://github.com/settings/tokens/new?scopes=read:packages&description=unwoke-pull>

Expiration: 90 days. Scope: `read:packages` only. Leave `repo` unchecked. A fine-grained token (`github_pat_…`) cannot pull GHCR. The login helper rejects it.

Store the token in a password manager. Do not commit it, paste it into an issue, or put it in a screenshot.

## Installed system

`rpm-ostree` and `bootc` both read `/etc/ostree/auth.json`. Automatic updates use that file. Nothing else has to be enabled.

```sh
ujust invite-login
```

The prompt does not echo the token and does not take it as an argument. It asks GitHub for `X-OAuth-Scopes` and refuses the token unless that header is exactly `read:packages`. It then checks that a pull of the booted image works, and writes the file as root, mode `600`.

Check without printing the secret:

```sh
ujust invite-status
sudo stat -c '%a %U' /etc/ostree/auth.json
```

You want `600 root`.

The file looks like this. The value is base64 of `login:token`. Do not invent a shorter substitute.

```json
{
  "auths": {
    "ghcr.io": {
      "auth": "<base64>"
    }
  }
}
```

`ujust invite-logout` deletes that file on this machine. It does not remove your GitHub access. Updates stop until you log in again.

## First switch

The owner tells you which image to rebase to. The names live in `.github/scripts/package-names.txt` in the private repository. After the credential file exists:

```sh
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/sergi270710267/IMAGE:latest
systemctl reboot
```

When `rpm-ostree status` shows a staged deployment, reboot once more. Verification:

```sh
cosign verify --key cosign.pub ghcr.io/sergi270710267/IMAGE
```

`cosign.pub` in this repository is the public key. It lets you check the signature. It does not let you pull. Old signatures may also exist on the public transparency log. The key check is the one that matters.

## USB

Download the Actions artifact with `gh` while you still have Read. Artifacts are deleted after 7 days. Check `SHA256SUMS` against `SHA256SUMS.sig` with `cosign verify-blob --key cosign.pub --insecure-ignore-tlog`. That flag skips the public log. It does not skip the signature.

Boot the ISO and start the installer. It asks for the same username and token before Anaconda. If the file is missing or is not mode `600`, the install stops. The credential is copied onto the new disk. It is not inside the image everyone would share.

## When access is removed

The next update fails. The system you already installed keeps running. The owner cannot remote-wipe it. Delete your classic token at <https://github.com/settings/tokens> so a copy of that token cannot be reused if you are invited again.

Sharing the token, or a copy of an image you already pulled, is outside what GitHub can stop. The MIT license on the overlay also allows redistribution of a copy you received. The Apache-2.0 notices on secureblue's files stay attached to those files. None of that adds people to the allowlist.
