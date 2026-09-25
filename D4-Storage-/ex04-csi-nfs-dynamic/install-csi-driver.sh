#!/usr/bin/env bash
# ex04 - install the upstream Kubernetes CSI NFS driver (a REAL CSI driver,
# unlike local-path-provisioner which predates the CSI spec and uses the
# older external-provisioner pattern). Talks to the same NFS server ex03
# used. Safe to re-run.
set -euo pipefail
VERSION="v4.13.4"
curl -skSL "https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/${VERSION}/deploy/install-driver.sh" \
  | bash -s "${VERSION}" --

echo
echo "Waiting for the driver to become Ready..."
kubectl -n kube-system rollout status deploy/csi-nfs-controller --timeout=90s
kubectl -n kube-system rollout status daemonset/csi-nfs-node --timeout=90s
kubectl get csidriver nfs.csi.k8s.io
