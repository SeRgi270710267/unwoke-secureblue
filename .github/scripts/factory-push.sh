#!/usr/bin/env bash
# Push a factory auto-commit (URL heal, snapshot refresh, relocated watch URL).
# github-actions[bot] is not a repository admin. ruleset main-strict therefore
# declines the push (GH013) unless GitHub Actions (app 15368) is a bypass actor.
# Do not auto-merge Dependabot. Do not add a new vendor host here.
set -euo pipefail

if git push origin HEAD; then
  exit 0
fi

echo "factory-push: declined. Repo → Settings → Rules → main-strict → Bypass list → GitHub Actions (Integration 15368), mode always. Owner admin bypass already lets a human/agent git push. Do not auto-merge Dependabot or a new vendor hostname." >&2
exit 1
