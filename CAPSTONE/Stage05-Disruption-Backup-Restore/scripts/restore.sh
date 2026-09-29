#!/usr/bin/env bash
# Restore the capstone app from a backup made by backup.sh.
# Works on an empty cluster: `kubectl delete namespace capstone` first to
# rehearse a real disaster.
#
# Order matters:
#   1. recreate everything from the backed-up config (app.yaml)
#   2. STOP redis before touching its volume. A running redis saves its
#      own (empty) data on shutdown and would overwrite the restore
#   3. copy the data in with a throw-away helper Pod that mounts the PVC
#   4. start redis: it loads the restored AOF files on startup
#
# usage: restore.sh <backup-dir>
set -euo pipefail
NS=capstone
SRC=${1:?usage: restore.sh <backup-dir>}
[ -d "$SRC/appendonlydir" ] && [ -f "$SRC/app.yaml" ] || { echo "not a backup dir: $SRC" >&2; exit 1; }
START=$(date +%s)

echo "[1/5] applying the backed-up config"
kubectl apply -f "$SRC/app.yaml" >/dev/null
kubectl -n "$NS" rollout status statefulset/redis --timeout=180s >/dev/null

echo "[2/5] stopping redis"
kubectl -n "$NS" scale statefulset/redis --replicas=0 >/dev/null
kubectl -n "$NS" wait --for=delete pod/redis-0 --timeout=90s >/dev/null 2>&1 || true

echo "[3/5] copying data into the volume via a helper Pod"
kubectl -n "$NS" delete pod restore-helper --ignore-not-found >/dev/null
kubectl -n "$NS" apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: restore-helper
  labels: { app.kubernetes.io/part-of: capstone }
spec:
  restartPolicy: Never
  containers:
    - name: helper
      image: redis:7-alpine          # already on the node; has sh + tar for kubectl cp
      command: ["sleep", "600"]
      volumeMounts: [ { name: data, mountPath: /data } ]
  volumes:
    - name: data
      persistentVolumeClaim: { claimName: data-redis-0 }
YAML
kubectl -n "$NS" wait --for=condition=Ready pod/restore-helper --timeout=120s >/dev/null
kubectl -n "$NS" exec restore-helper -- sh -c 'rm -rf /data/appendonlydir /data/dump.rdb'
kubectl -n "$NS" cp "$SRC/appendonlydir" restore-helper:/data/appendonlydir 2>/dev/null
kubectl -n "$NS" delete pod restore-helper --now >/dev/null

echo "[4/5] starting redis"
kubectl -n "$NS" scale statefulset/redis --replicas=1 >/dev/null
kubectl -n "$NS" rollout status statefulset/redis --timeout=180s >/dev/null
kubectl -n "$NS" rollout status deploy/api --timeout=180s >/dev/null
kubectl -n "$NS" rollout status deploy/web --timeout=180s >/dev/null

echo "[5/5] checking"
GOT=$(kubectl -n "$NS" exec redis-0 -- redis-cli GET hits | tr -d '\r')
WANT=$(awk '/^hits:/{print $2}' "$SRC/backup-info.txt")
echo "counter in backup: $WANT   counter now: $GOT"
echo "restore took $(( $(date +%s) - START )) s"
[ "$GOT" = "$WANT" ] && echo "RESTORE OK" || { echo "RESTORE MISMATCH" >&2; exit 1; }
