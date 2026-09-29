#!/usr/bin/env bash
# Drill S5 setup: stop redis, fill the node's free CPU with one low-priority
# filler Pod (leaving 50m, less than redis's 110m), then start redis again.
# redis (priority 100000) can only be scheduled by preempting the filler (-100).
#
# usage: fill-node.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')

echo "[1/4] stopping redis so its own request doesn't count as free space"
kubectl -n capstone scale statefulset/redis --replicas=0 >/dev/null
kubectl -n capstone wait --for=delete pod/redis-0 --timeout=90s >/dev/null 2>&1 || true

echo "[2/4] measuring free CPU on $NODE"
ALLOC=$(kubectl get node "$NODE" -o jsonpath='{.status.allocatable.cpu}')
case "$ALLOC" in *m) ALLOC_M=${ALLOC%m} ;; *) ALLOC_M=$(( ALLOC * 1000 )) ;; esac
USED_M=$(kubectl describe node "$NODE" | awk '/Allocated resources/{f=1} f && $1=="cpu"{sub("m","",$2); print $2; exit}')
FILL_M=$(( ALLOC_M - USED_M - 50 ))
echo "      allocatable ${ALLOC_M}m, requested ${USED_M}m -> filler requests ${FILL_M}m"

echo "[3/4] creating the filler (priority -100)"
sed "s/FILL_CPU/${FILL_M}m/" "$HERE/preemption-filler.yaml" | kubectl apply -f - >/dev/null
kubectl -n capstone-filler rollout status deploy/filler --timeout=90s >/dev/null
kubectl describe node "$NODE" | awk '/Allocated resources/{f=1} f && $1=="cpu"{print "      node cpu requests now: "$2" "$3; exit}'

echo "[4/4] starting redis (needs 110m, only 50m free)"
kubectl -n capstone scale statefulset/redis --replicas=1 >/dev/null
