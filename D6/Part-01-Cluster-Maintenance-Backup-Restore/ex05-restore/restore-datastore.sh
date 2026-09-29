#!/usr/bin/env bash
# ex05 - restore this node's k3s datastore from a backup made by
# ex04-backup/backup-datastore.sh. Stops k3s, moves the CURRENT server
# directory aside (never deletes it outright - so a bad restore is itself
# recoverable), extracts the backup tarball in its place, then starts k3s.
#
# Usage: restore-datastore.sh /root/k3s-backups/k3s-server-<stamp>.tar.gz
set -euo pipefail

BACKUP_FILE="${1:?Usage: $0 <path-to-backup.tar.gz>}"
SERVER_DIR="/var/lib/rancher/k3s/server"
SIDESTEP="${SERVER_DIR}.before-restore-$(date +%s)"

if ! sudo test -f "${BACKUP_FILE}"; then
  echo "Backup file not found: ${BACKUP_FILE}" >&2
  exit 1
fi

echo "Stopping k3s..."
sudo systemctl stop k3s

echo "Moving current state aside (not deleting) -> ${SIDESTEP}"
sudo mv "${SERVER_DIR}" "${SIDESTEP}"

echo "Extracting ${BACKUP_FILE} -> ${SERVER_DIR}"
sudo mkdir -p "${SERVER_DIR}"
sudo tar xzf "${BACKUP_FILE}" -C "${SERVER_DIR}"

echo "Starting k3s..."
sudo systemctl start k3s

echo "Waiting for the API to come back..."
for i in $(seq 1 30); do
  kubectl get nodes >/dev/null 2>&1 && { echo "API back after ~$((i*2))s"; break; }
  sleep 2
done

echo
echo "Restore complete. Pre-restore state kept at: ${SIDESTEP}"
echo "(delete it once you've confirmed the restore is good)"
