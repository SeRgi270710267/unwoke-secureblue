# Name and logo

The name **Unwoke SecureBlue**, the wordmark, and the logo files in `docs/assets/` (`logo.svg`, `wordmark.svg`, `hero.jpg`) name the builds signed with this repository's cosign key.

You may read this public repository. A rebuild that is not signed by `cosign.pub` in this repository is not an official build. Do not use the name, the wordmark, or the logo for that rebuild. Pick another name and replace the logo before you ship it.

`cosign verify --key cosign.pub` succeeds only for images signed with the private key held as the GitHub secret `SIGNING_SECRET`. A rebuild can still be installed with an unverified rebase. It will not verify as this project.

This is not a claim on the word "secureblue". That name belongs to the secureblue project. This project is not affiliated with them. Their Apache-2.0 files keep their notices. This file does not relicense those files.

## License, left as MIT

The overlay's own files stay under the MIT license in `LICENSE`. That is a decision, not an oversight.

- Copies already shipped under MIT keep that grant. Replacing `LICENSE` later does not take it back.
- The installed system includes secureblue's Apache-2.0 image. That license allows those parts to be redistributed with their notices. An overlay license cannot cancel that.
- Git history is `SeRgi270710267`, commits titled as Cursor Agent, and Dependabot pin bumps. No other human author showed up in `git shortlog`. Relicensing would still be the owner's act, and it should not be done by an agent in passing. Dependabot did not write the overlay. Agent commits were made for this repository's owner.
- A license that says "do not redistribute builds" on a public git tree is a legal claim after the fact. GitHub will still serve the files. It does not stop a pull of the source.

A different license for future overlay files is possible only if the owner chooses it and says so in `LICENSE`. Apache-2.0 files, including `files/upstream-snapshots/` and the ISO hook's SPDX header, stay Apache-2.0.
