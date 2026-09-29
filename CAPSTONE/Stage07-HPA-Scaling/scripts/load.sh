#!/usr/bin/env bash
# Generate CPU load on the API tier from OUTSIDE the cluster, through the
# Ingress, the same path real users take (Traefik -> web -> api).
#
# Each request asks the api for MS milliseconds of busy CPU (/api/cpu).
# WORKERS loops run in parallel for DURATION seconds.
#
# usage: load.sh [workers=4] [duration=180] [ms=200]
set -euo pipefail
WORKERS=${1:-4}; DURATION=${2:-180}; MS=${3:-200}
NODE_IP=${NODE_IP:-$(hostname -I | awk '{print $1}')}
URL="http://capstone.k3s.local/api/cpu?ms=$MS"
END=$(( $(date +%s) + DURATION ))
echo "load: $WORKERS workers x ${MS}ms CPU per request, ${DURATION}s, via $NODE_IP"
for w in $(seq 1 "$WORKERS"); do
  ( n=0; while [ "$(date +%s)" -lt "$END" ]; do
      curl -s -o /dev/null --resolve "capstone.k3s.local:80:$NODE_IP" "$URL" && n=$((n+1))
    done; echo "worker $w: $n requests" ) &
done
wait
echo "load: done"
