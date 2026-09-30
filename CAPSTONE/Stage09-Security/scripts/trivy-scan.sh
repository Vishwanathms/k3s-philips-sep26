#!/usr/bin/env bash
# Stage 09: scan the three images the capstone actually runs for known
# HIGH/CRITICAL vulnerabilities.
#
# Runs Trivy in Docker (the same Docker that built and pushed the images in
# Stage 01), with --network host so it can reach the local registry on
# localhost:5000. --insecure because that registry speaks plain HTTP.
# Trivy is pinned so a re-run compares like with like; the vulnerability
# database it downloads is always the latest.
#
# usage: trivy-scan.sh [--summary]
set -euo pipefail
TRIVY=aquasec/trivy:0.74.0
IMAGES=(
  localhost:5000/capstone-web:1.0.0
  localhost:5000/capstone-api:1.0.0
  redis:7-alpine
)

# A named volume keeps the vulnerability DB between runs (first run ~1 min).
for img in "${IMAGES[@]}"; do
  echo "=== $img"
  if [ "${1:-}" = "--summary" ]; then
    docker run --rm --network host -v trivy-cache:/root/.cache "$TRIVY" image \
      --quiet --insecure --severity HIGH,CRITICAL --format json "$img" |
      python3 -c 'import json,sys,collections
d=json.load(sys.stdin); c=collections.Counter(v["Severity"] for r in d.get("Results",[]) for v in r.get("Vulnerabilities") or [])
print("  HIGH:", c["HIGH"], " CRITICAL:", c["CRITICAL"])'
  else
    docker run --rm --network host -v trivy-cache:/root/.cache "$TRIVY" image \
      --quiet --insecure --severity HIGH,CRITICAL "$img"
  fi
done
