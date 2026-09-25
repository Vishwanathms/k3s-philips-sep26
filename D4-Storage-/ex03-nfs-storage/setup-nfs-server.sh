#!/usr/bin/env bash
# ex03 - create the NFS share this lab (and ex04's CSI driver) mounts from.
# Installs a real NFS server ON THIS NODE and exports one directory. Safe
# to re-run: exportfs -ra reloads /etc/exports idempotently.
#
# Exported to three ranges, all required:
#   - the Pod CIDR (10.42.0.0/16)     - in case anything ever mounts NFS
#                                        directly from a Pod's own IP
#   - the node's own subnet            - REQUIRED: the in-tree Kubernetes
#                                        NFS volume plugin has the kubelet
#                                        (on the node's IP, not a Pod IP)
#                                        perform the mount. Without this,
#                                        every mount fails with
#                                        "mount.nfs: access denied by server"
#                                        (see OUTPUT.md for the real error).
#   - 127.0.0.1                        - lets you test the export locally
#                                        with `showmount -e localhost`
#
# NODE_SUBNET and the export path come from ../env.sh, which auto-detects
# them from this node. Override either by exporting it first:
#
#     NODE_SUBNET=192.168.230.0/23 bash setup-nfs-server.sh
set -euo pipefail

# shellcheck source=../env.sh
source "$(dirname "$0")/../env.sh"

EXPORT_DIR="${NFS_EXPORT_DIR}"
POD_CIDR="${POD_CIDR:-10.42.0.0/16}"

echo "Installing nfs-kernel-server (no-op if already installed)..."
sudo apt-get update -qq
sudo apt-get install -y -qq nfs-kernel-server

echo "Creating and permissioning ${EXPORT_DIR}..."
sudo mkdir -p "${EXPORT_DIR}"
sudo chown nobody:nogroup "${EXPORT_DIR}"
sudo chmod 0777 "${EXPORT_DIR}"

echo "Writing /etc/exports..."
EXPORT_LINE="${EXPORT_DIR} ${POD_CIDR}(rw,sync,no_subtree_check,no_root_squash) ${NODE_SUBNET}(rw,sync,no_subtree_check,no_root_squash) 127.0.0.1(rw,sync,no_subtree_check,no_root_squash)"
echo "${EXPORT_LINE}" | sudo tee /etc/exports >/dev/null

echo "Reloading exports and (re)starting the server..."
sudo exportfs -ra
sudo systemctl enable --now nfs-kernel-server >/dev/null

echo
echo "Done. Current exports:"
sudo exportfs -v
echo
echo "Server status:"
systemctl is-active nfs-kernel-server
