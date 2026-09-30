#!/usr/bin/env bash
# Stage12-GitHub G1: push this stage's gitops/ to a real GitHub repo,
# over SSH using this VM's existing deploy key (added to the repo with
# write access - see LAB-MANUAL.md G1). Mirrors Stage12-ArgoCD's
# setup-git-remote.sh, but against github.com instead of the local
# git-daemon stand-in, and into its own clone directory so the two
# stages' git history never mixes.
set -euo pipefail

STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE_URL="git@github.com:Vishwanathms/k3s-helm-argocd-capstone.git"
CLONE_DIR="$HOME/capstone-gitops-github-clone"

# github.com's SSH always exits 1 here (no shell access) even on success,
# so check the greeting text, not the exit code (and don't let `set -e`
# or pipefail trip on that expected nonzero exit).
ssh_greeting="$(ssh -o BatchMode=yes -T git@github.com 2>&1 || true)"
if ! grep -q "successfully authenticated" <<<"$ssh_greeting"; then
  echo "SSH to github.com failed - is the deploy key added to the repo?" >&2
  echo "$ssh_greeting" >&2
  exit 1
fi

if [ ! -d "$CLONE_DIR/.git" ]; then
  if git ls-remote "$REMOTE_URL" >/dev/null 2>&1 && [ -n "$(git ls-remote "$REMOTE_URL")" ]; then
    git clone "$REMOTE_URL" "$CLONE_DIR"
  else
    mkdir -p "$CLONE_DIR"
    git -C "$CLONE_DIR" init --initial-branch=main
    git -C "$CLONE_DIR" remote add origin "$REMOTE_URL"
  fi
fi

rsync -a --delete --exclude .git "$STAGE_DIR/gitops/" "$CLONE_DIR/"

cd "$CLONE_DIR"
git add -A
if ! git diff --cached --quiet; then
  git -c user.email=labuser@lab-g2-vm2 -c user.name=labuser commit -m "capstone-github gitops: sync from CAPSTONE/Stage12-GitHub/gitops"
else
  echo "clone already matches Stage12-GitHub/gitops - nothing to commit" >&2
fi
git push -u origin main

echo "Remote: $REMOTE_URL"
echo "Clone:  $CLONE_DIR"
