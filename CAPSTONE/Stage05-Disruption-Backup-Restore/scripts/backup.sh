#!/usr/bin/env bash
# Back up the capstone app: its DATA (redis) and its exact CONFIG.
#
#   data   -> <dest>/appendonlydir/   redis's append-only files, compacted first
#   config -> <dest>/app.yaml         the manifests that were deployed
#   info   -> <dest>/backup-info.txt  when, which images, counter value
#
# Why appendonlydir and not dump.rdb? Our redis runs with --appendonly yes,
# and on startup redis 7 loads ONLY the AOF files; a dump.rdb is ignored.
# Back up what redis actually loads.
#
# usage: backup.sh [dest-dir]     default: ~/capstone-backups/<timestamp>
set -euo pipefail
NS=capstone
HERE=$(cd "$(dirname "$0")" && pwd)
DEST=${1:-$HOME/capstone-backups/$(date +%Y%m%d-%H%M%S)}
mkdir -p "$DEST"

rcli() { kubectl -n "$NS" exec redis-0 -- redis-cli "$@" | tr -d '\r'; }

echo "[1/4] compacting the AOF (BGREWRITEAOF)"
rcli BGREWRITEAOF >/dev/null
until [ "$(rcli INFO persistence | awk -F: '/^aof_rewrite_in_progress/{print $2}')" = 0 ]; do sleep 1; done

HITS=$(rcli GET hits)
echo "[2/4] copying redis data (counter = ${HITS:-<unset>})"
kubectl -n "$NS" cp redis-0:/data/appendonlydir "$DEST/appendonlydir" 2>/dev/null

echo "[3/4] saving the deployed config"
for f in "$HERE"/../manifests/*.yaml; do echo "---"; cat "$f"; done > "$DEST/app.yaml"

echo "[4/4] writing backup-info.txt"
{
  echo "date:   $(date -Is)"
  echo "hits:   ${HITS}"
  echo "images:"
  kubectl -n "$NS" get pods -o jsonpath='{range .items[*]}  {.metadata.name}: {.spec.containers[0].image}{"\n"}{end}'
} > "$DEST/backup-info.txt"

echo
echo "backup complete: $DEST"
ls -l "$DEST" "$DEST/appendonlydir"
