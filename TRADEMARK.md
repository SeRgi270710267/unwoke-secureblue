# Name and logo

The name **Unwoke SecureBlue**, the wordmark, and the logo files in `docs/assets/` (`logo.svg`, `wordmark.svg`, `hero.jpg`) name the builds signed with this repository's cosign key.

You may read this public repository. A rebuild that is not signed by `cosign.pub` in this repository is not an official build. Do not use the name, the wordmark, or the logo for that rebuild. Pick another name and replace the logo before you ship it.

`cosign verify --key cosign.pub` succeeds only for images signed with the private key held as the GitHub secret `SIGNING_SECRET`. A rebuild can still be installed with an unverified rebase. It will not verify as this project.

This is not a claim on the word "secureblue". That name belongs to the secureblue project. This project is not affiliated with them. Their Apache-2.0 files keep their notices. This file does not relicense those files.

## License

The overlay is the Unwoke Source-Available License 1.0 in `LICENSE`. It is not an OSI license. It allows reading and a private build. It does not allow redistributing the overlay or a build that includes it, or using this name and logo, without permission.

Earlier public versions were published under the MIT license. A copy already obtained under that grant keeps it.

Apache-2.0 section 4 lets this project set different terms on its own work. It does not cancel Apache-2.0 on secureblue's files. `NOTICE` lists those paths. They stay Apache-2.0, including the right to redistribute those files alone. secureblue's live branch has a LICENSE and no NOTICE file.

The copyright holder is the sole human author. Agent commits and Dependabot pin bumps were made on that author's behalf. The Apache-2.0 files were not relicensed.

GitHub will still serve this public tree, and the Fork button will still work. The license is a limit on what a reader may do. It is not a technical lock.
