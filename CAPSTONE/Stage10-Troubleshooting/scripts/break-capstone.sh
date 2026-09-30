#!/usr/bin/env bash
# Instructor tool: inject 5 real faults into a healthy `capstone` namespace,
# one per tier/object, each a genuine mistake this course has actually
# discussed on an earlier day. Every fault is a live `kubectl patch` - no
# manifest in this repo is ever wrong.
#
# Faults (see LAB-MANUAL.md for the diagnosis path for each):
#   1. Service/web        selector no longer matches any Pod (typo)
#   2. Deployment/api      image tag doesn't exist (bad release)
#   3. NetworkPolicy/api   ingress port doesn't match the container port
#   4. StatefulSet/redis   memory limit far below what redis needs (OOM)
#   5. Deployment/web      readinessProbe path doesn't exist (typo)
#
# Idempotent: re-running re-applies the same 5 patches without erroring.
# usage: break-capstone.sh
set -euo pipefail
NS=capstone

echo "[1/5] Service/web: selector typo (app=web -> app=web-tier)"
kubectl -n "$NS" patch service web --type=merge -p '{"spec":{"selector":{"app":"web-tier"}}}'

echo "[2/5] Deployment/api: bad image tag"
kubectl -n "$NS" set image deployment/api api=localhost:5000/capstone-api:9.9.9-missing

echo "[3/5] NetworkPolicy/api: ingress port doesn't match the container's 8000"
kubectl -n "$NS" patch networkpolicy api --type=json \
  -p='[{"op":"replace","path":"/spec/ingress/0/ports/0/port","value":8001}]'

echo "[4/5] StatefulSet/redis: memory request+limit cut from 128Mi to 8Mi"
kubectl -n "$NS" patch statefulset redis --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/memory","value":"8Mi"},
       {"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"8Mi"}]'

echo "[5/5] Deployment/web: readinessProbe path typo (/healthz -> /healthzz)"
kubectl -n "$NS" patch deployment web --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/healthzz"}]'

echo
echo "5 faults injected. The site is now broken in more than one way at"
echo "once - that's real. Start with: kubectl -n $NS get pods,svc,endpoints"
