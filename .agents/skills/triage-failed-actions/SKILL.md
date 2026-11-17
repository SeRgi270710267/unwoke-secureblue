---
name: triage-failed-actions
description: Classifies a red Unwoke SecureBlue Actions run. Use when a workflow, factory-alarm, or iso-alarm is red.
---

# Triage failed Actions

1. **List.** `gh run list --status failure --limit 20`. Ignore runs whose commit is no longer the branch head.
2. **Read** the failed log. Do not paste tokens, signing keys, or registry credentials into a public issue or the pull request.
3. **Classify.**
   - Download blip (504, curl 22/35, cut-off tar, slsa-verifier) on attempt 1: `flake-rerun` retries those jobs once. Do not also dispatch a second full bake.
   - Attempt 2 still red, or a canary needle, or a signing-key mismatch: leave `factory-alarm` open. Do not delete needles or accept a new `keys/secureblue.pub` to go green.
   - `iso-alarm`: the USB wrap failed. Do not bump titanoboa. A one-image dispatch that succeeds does not close the weekly failure.
   - `stock-feats`: read their patch. Set `stock_reviewed: keep` or `adopted` in `docs/_tools/stock-feats.json`. Do not auto-copy.
   - Expired secret (`SIGNING_SECRET` or a model key): tell the maintainer the secret name and where to set it. Do not invent a value or weaken verification.
   - Pull request gate: fix the branch. Do not weaken the check to pass.
4. **Report** what failed, why, and what the maintainer must do. Do not close the alarm issue yourself unless the matching green run is what closes it.
