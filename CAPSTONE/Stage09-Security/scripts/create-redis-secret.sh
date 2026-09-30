#!/usr/bin/env bash
# Stage 09: create the redis password Secret with a random value.
#
# The password is generated here, on your VM, and goes straight into the
# cluster. It is never written to a file in this repo: a manifest with a
# real password in it is a leaked password the moment it's committed.
#
# Safe to re-run: an existing Secret is kept (changing the password under a
# running redis would lock the api out until everything restarts).
set -euo pipefail
NS=capstone

if ! kubectl get namespace "$NS" >/dev/null 2>&1; then
  echo "namespace $NS missing: kubectl apply -f manifests/00-namespace.yaml first" >&2
  exit 1
fi

if kubectl -n "$NS" get secret redis-auth >/dev/null 2>&1; then
  echo "secret/redis-auth already exists - kept"
  exit 0
fi

kubectl -n "$NS" create secret generic redis-auth \
  --from-literal=password="$(openssl rand -hex 24)"
kubectl -n "$NS" label secret redis-auth app.kubernetes.io/part-of=capstone
