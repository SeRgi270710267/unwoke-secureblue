# GEMINI.md

Before changing this repository, read these in order:

1. `AGENTS.md` (what this overlay is, checks, factory rules, hard no)
2. `PROGRESS.md` (handoff and what not to redo)
3. `CONTRIBUTING.md` and `SECURITY.md`

Skills live in `.agents/skills/` (`ship-a-pr`, `triage-failed-actions`, `add-a-lock`). Workspace rules are in `.agents/rules/`.

Do not print or commit `SIGNING_SECRET`, `cosign.key`, or a pull token. Do not set `gpgcheck=0` or `setenforce 0`. Do not move the image-builder pin or the titanoboa pin unless the maintainer asked. Maintainer merge only.
