# Name and logo

The name **Unwoke SecureBlue**, the wordmark, and the logo files in `docs/assets/` (`logo.svg`, `wordmark.svg`, `hero.jpg`) name the builds signed with this repository's cosign key.

You may read this public repository. A rebuild that is not signed by `cosign.pub` in this repository is not an official build. Do not use the name, the wordmark, or the logo for that rebuild. Pick another name and replace the logo before you ship it.

`cosign verify --key cosign.pub` succeeds only for images signed with the private key held as the GitHub secret `SIGNING_SECRET`. A rebuild can still be installed with an unverified rebase. It will not verify as this project.

This is not a claim on the word "secureblue". That name belongs to the secureblue project. This project is not affiliated with them. Their Apache-2.0 files keep their notices. This file does not relicense those files.

## License

Overlay material through commit `d0dc4d4fd33e91b664a95a83795169fa70b3741a` stays MIT (`LICENSE-MIT`). That grant is not revoked.

Later overlay changes are the Unwoke Source-Available License 1.0 in `LICENSE`. It is not an OSI license. It allows reading and a private build. It does not allow redistributing the overlay or a build that includes it, or using this name and logo, without permission.

PolyForm Noncommercial still allows noncommercial redistribution. PolyForm Strict still allows redistribution that is not "competing use." Neither matches "no redistribution of builds without permission," so those texts were not used.

Apache-2.0 section 4 lets us set different terms for our own modifications. It does not let us cancel Apache-2.0 on secureblue's files. `NOTICE` lists those paths. They stay Apache-2.0, including the right to redistribute those files alone. secureblue's live branch has a LICENSE and no NOTICE file.

Git history is this account, agent commits made for it, and Dependabot pin bumps. No other human author showed up. The new license is the owner's terms for later overlay changes. It does not relicense the Apache files or the MIT copies already granted.

GitHub will still serve this public tree, and the Fork button will still work. The license is a limit on what a reader may do with later overlay files. It is not a technical lock.
