#!/usr/bin/env bash
# Stage13 S1: add app/ and .github/workflows/ to the existing GitHub clone
# (~/capstone-gitops-github-clone, set up by Stage12-GitHub-argocd's
# setup-github-remote.sh) alongside the chart that's already there, and
# push. Unlike that script, this one does NOT wipe the whole clone first
# (no --delete on the clone root) - it only mirrors the app/ and
# .github/ subtrees, so chart/, kustomization.yaml and values-github.yaml
# are left untouched.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"   # k3s-training/
STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLONE_DIR="$HOME/capstone-gitops-github-clone"

if [ ! -d "$CLONE_DIR/.git" ]; then
  echo "Expected an existing clone at $CLONE_DIR (from Stage12-GitHub-argocd's" >&2
  echo "setup-github-remote.sh). Run that first." >&2
  exit 1
fi

ssh_greeting="$(ssh -o BatchMode=yes -T git@github.com 2>&1 || true)"
if ! grep -q "successfully authenticated" <<<"$ssh_greeting"; then
  echo "SSH to github.com failed - is the deploy key still added?" >&2
  echo "$ssh_greeting" >&2
  exit 1
fi

mkdir -p "$CLONE_DIR/app" "$CLONE_DIR/.github/workflows"
rsync -a --delete "$REPO_ROOT/CAPSTONE/app/" "$CLONE_DIR/app/"
rsync -a --delete "$STAGE_DIR/workflows/" "$CLONE_DIR/.github/workflows/"

cd "$CLONE_DIR"
git add -A
if git diff --cached --quiet; then
  echo "clone already matches app/ + workflow - nothing to commit" >&2
else
  git -c user.email=labuser@lab-g2-vm2 -c user.name=labuser commit \
    -m "capstone-ci: add app/ source and build-and-deploy workflow (Stage13)"
fi
git push -u origin main

echo "Remote: git@github.com:Vishwanathms/k3s-helm-argocd-capstone.git"
echo "Clone:  $CLONE_DIR"
