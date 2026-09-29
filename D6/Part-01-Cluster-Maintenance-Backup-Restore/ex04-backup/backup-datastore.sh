#!/usr/bin/env bash
# ex04 - back up this node's k3s datastore.
#
# k3s's default datastore for a single server is embedded SQLite (via
# "kine"), NOT etcd. `k3s etcd-snapshot` only works with embedded-etcd
# clusters (--cluster-init) - it will refuse to run here (see OUTPUT.md).
# For SQLite, the officially documented approach is a plain file-level
# backup of the whole server directory, taken while k3s is stopped so the
# copy is internally consistent. This backs up:
#   - db/         the SQLite state (every object in the cluster)
#   - tls/        certificates and keys
#   - token       the node/cluster join secret
# Causes a short real API outage for the duration of the copy (a few
# seconds on this node's data size).
set -euo pipefail

BACKUP_DIR="${1:-/root/k3s-backups}"
STAMP=$(date +%Y%m%d-%H%M%S)
DEST="${BACKUP_DIR}/k3s-server-${STAMP}.tar.gz"

echo "Confirming this cluster uses SQLite, not etcd..."
sudo k3s etcd-snapshot save 2>&1 | tail -3 || true
echo

echo "Stopping k3s..."
sudo systemctl stop k3s

echo "Archiving /var/lib/rancher/k3s/server -> ${DEST}"
sudo mkdir -p "${BACKUP_DIR}"
sudo tar czf "${DEST}" -C /var/lib/rancher/k3s/server . 2>&1 | grep -v 'socket ignored' || true

echo "Starting k3s..."
sudo systemctl start k3s

echo "Waiting for the API to come back..."
for i in $(seq 1 30); do
  kubectl get nodes >/dev/null 2>&1 && { echo "API back after ~$((i*2))s"; break; }
  sleep 2
done

echo
echo "Backup written to: ${DEST}"
sudo ls -la "${DEST}"
