#!/usr/bin/env bash
# Stage12-GitHub G2: give Argo CD's repo-server its own credential for the
# private GitHub repo, as a Secret in the argocd namespace (the standard
# Argo CD convention: label argocd.argoproj.io/secret-type=repository).
#
# Reuses this VM's existing SSH key (already added to the repo as a
# read+write deploy key) - the key is read straight from disk into the
# Secret via --from-file, never echoed to a terminal or committed anywhere.
set -euo pipefail
REPO_URL="git@github.com:Vishwanathms/k3s-helm-argocd-capstone.git"
SECRET_NAME="capstone-github-repo-creds"

if kubectl -n argocd get secret "$SECRET_NAME" >/dev/null 2>&1; then
  echo "secret/$SECRET_NAME already exists in argocd ns - kept"
  exit 0
fi

kubectl -n argocd create secret generic "$SECRET_NAME" \
  --from-literal=type=git \
  --from-literal=url="$REPO_URL" \
  --from-file=sshPrivateKey="$HOME/.ssh/id_rsa"

kubectl -n argocd label secret "$SECRET_NAME" argocd.argoproj.io/secret-type=repository

echo "Argo CD repository credential created for $REPO_URL"
