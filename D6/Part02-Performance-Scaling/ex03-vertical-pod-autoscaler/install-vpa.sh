#!/usr/bin/env bash
# ex03 - install the upstream Kubernetes VPA (Vertical Pod Autoscaler).
# Unlike metrics-server, VPA does NOT ship with k3s - every student's own
# lab cluster needs this run once before Lab 3 in LAB-MANUAL.md. Safe to
# re-run (helm upgrade path is idempotent; sparse-checkout re-clones clean).
set -euo pipefail

WORKDIR="${WORKDIR:-/tmp/autoscaler}"

echo "--- 1/4: checking prerequisites (k3s, metrics-server, helm) ---"
kubectl get nodes
kubectl top node
helm version --short

echo "--- 2/4: sparse-cloning kubernetes/autoscaler (vertical-pod-autoscaler chart only) ---"
rm -rf "$WORKDIR"
git clone --filter=blob:none --sparse https://github.com/kubernetes/autoscaler.git "$WORKDIR"
cd "$WORKDIR"
git sparse-checkout set vertical-pod-autoscaler

echo "--- 3/4: installing VPA into kube-system ---"
helm install vpa vertical-pod-autoscaler/charts/vertical-pod-autoscaler -n kube-system

echo "--- 4/4: waiting for VPA components to become Ready ---"
kubectl -n kube-system rollout status deployment/vpa-recommender --timeout=90s
kubectl -n kube-system rollout status deployment/vpa-updater --timeout=90s
kubectl -n kube-system rollout status deployment/vpa-admission-controller --timeout=90s

echo
echo "VPA CRDs:"
kubectl get crd | grep autoscaling.k8s.io
echo
echo "VPA Pods:"
kubectl -n kube-system get pods -l app.kubernetes.io/name=vertical-pod-autoscaler
