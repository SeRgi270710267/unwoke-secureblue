#!/bin/sh
# Install a pre-commit hook that runs the secret scan on staged files.
# CI runs the same scan. Re-run this after clone if you want the local check.
set -eu

root=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
hook="$root/.git/hooks/pre-commit"
mkdir -p "$root/.git/hooks"
cat > "$hook" <<'EOF'
#!/bin/sh
# Installed by .github/scripts/install_git_hooks.sh
set -eu
root=$(git rev-parse --show-toplevel)
python3 "$root/.github/scripts/secret_scan.py" --staged
EOF
chmod +x "$hook"
echo "installed $hook"
