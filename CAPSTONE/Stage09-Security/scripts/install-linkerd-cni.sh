#!/usr/bin/env bash
# Stage 09, one-time node step: move Linkerd's iptables setup out of every
# Pod and into a CNI plugin.
#
# Why: by default every meshed Pod gets a `linkerd-init` container with
# NET_ADMIN + NET_RAW, so it can rewrite that Pod's iptables. Pod Security
# Admission rejects those capabilities at BOTH `baseline` and `restricted`.
# With linkerd-cni, a node-level DaemonSet (namespace linkerd-cni, which is
# allowed to be privileged) does that job when the Pod's network is created,
# and Pods get a harmless `linkerd-network-validator` init container instead.
#
# k3s keeps its CNI files in non-default places; the paths below come from
# /var/lib/rancher/k3s/agent/etc/containerd/config.toml (bin_dirs/conf_dir).
#
# Safe to re-run. Existing Pods keep working until they are restarted.
set -euo pipefail
export PATH=$HOME/.linkerd2/bin:$PATH

CNI_NET_DIR=/var/lib/rancher/k3s/agent/etc/cni/net.d
CNI_BIN_DIR=/var/lib/rancher/k3s/data/cni

echo "[1/4] install the linkerd-cni DaemonSet"
linkerd install-cni \
  --dest-cni-net-dir="$CNI_NET_DIR" \
  --dest-cni-bin-dir="$CNI_BIN_DIR" | kubectl apply -f -
kubectl -n linkerd-cni rollout status daemonset/linkerd-cni --timeout=120s

echo "[2/4] the plugin is now chained after flannel"
sudo grep -o '"type": *"linkerd-cni"' "$CNI_NET_DIR"/10-flannel.conflist

echo "[3/4] tell the control plane: inject without linkerd-init from now on"
linkerd upgrade --linkerd-cni-enabled | kubectl apply -f -
kubectl -n linkerd rollout status deploy/linkerd-proxy-injector --timeout=120s
kubectl -n linkerd rollout status deploy/linkerd-destination --timeout=120s
kubectl -n linkerd rollout status deploy/linkerd-identity --timeout=120s

echo "[4/4] check"
linkerd check 2>&1 | tail -5
echo
echo "Done. Restart meshed workloads to drop linkerd-init, e.g.:"
echo "  kubectl -n linkerd-viz rollout restart deploy"
