#!/usr/bin/env bash
# D1: prove Argo CD self-heals a manual kubectl drift, without touching git.
set -euo pipefail
NS=capstone

echo "-- before: web replicas --"
kubectl -n "$NS" get deploy web -o jsonpath='{.spec.replicas}{"\n"}'

echo "-- drifting: kubectl scale to 5 (not through git) --"
kubectl -n "$NS" scale deploy/web --replicas=5

echo "-- forcing an Argo CD refresh so this drill doesn't wait out the default 3m poll --"
kubectl -n argocd annotate application capstone argocd.argoproj.io/refresh=hard --overwrite
sleep 8

echo "-- after: web replicas (Argo CD should have put this back to what git says) --"
kubectl -n "$NS" get deploy web -o jsonpath='{.spec.replicas}{"\n"}'
kubectl -n argocd get application capstone -o jsonpath='sync={.status.sync.status} health={.status.health.status}{"\n"}'
